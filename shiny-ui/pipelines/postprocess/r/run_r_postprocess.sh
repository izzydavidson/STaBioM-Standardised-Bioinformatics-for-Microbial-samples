#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# STaBioM R Postprocess Runner (Unified for all pipelines)
# Configurable R-based postprocessing for sr_amp, sr_meta, and lr_meta modules
# Outputs to standardized results/ structure
# =============================================================================

usage() {
  cat <<'EOF'
Usage:
  run_r_postprocess.sh --config <config.json> --outputs <outputs.json> --module <sr_amp|sr_meta|lr_meta>

Runs configurable R postprocessing steps after a module completes.
Outputs are written to a standardized results/ directory structure.

Config schema (postprocess section):
  postprocess:
    enabled: 0|1 (default 0)
    rscript_bin: "Rscript" (default)
    steps:
      heatmap: 0|1
      piechart: 0|1
      relative_abundance: 0|1
      stacked_bar: 0|1
      results_csv: 0|1
      valencia: 0|1 (only runs if valencia outputs exist)

Output layout (standardized for all pipelines):
  <run_dir>/results/plots/        - All generated plots
  <run_dir>/results/tables/       - All generated tables
  <run_dir>/results/valencia/     - Valencia outputs (if enabled)
  <run_dir>/results/manifest.json - Manifest of all outputs
  <run_dir>/<module>/logs/r_postprocess/<step_name>.log

EOF
}

CONFIG_PATH=""
OUTPUTS_JSON=""
MODULE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --outputs) OUTPUTS_JSON="${2:-}"; shift 2 ;;
    --module) MODULE_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# Validate arguments
if [[ -z "${CONFIG_PATH}" ]]; then echo "ERROR: --config is required" >&2; usage; exit 2; fi
if [[ -z "${OUTPUTS_JSON}" ]]; then echo "ERROR: --outputs is required" >&2; usage; exit 2; fi
if [[ -z "${MODULE_NAME}" ]]; then echo "ERROR: --module is required" >&2; usage; exit 2; fi
if [[ ! -f "${CONFIG_PATH}" ]]; then echo "ERROR: Config not found: ${CONFIG_PATH}" >&2; exit 2; fi
if [[ ! -f "${OUTPUTS_JSON}" ]]; then echo "ERROR: Outputs not found: ${OUTPUTS_JSON}" >&2; exit 2; fi
if ! command -v jq >/dev/null 2>&1; then echo "ERROR: jq is required but not found in PATH" >&2; exit 2; fi
if ! command -v python3 >/dev/null 2>&1; then echo "ERROR: python3 is required but not found in PATH" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine paths from outputs.json
read -r MODULE_DIR RUN_DIR <<< "$(python3 - "${OUTPUTS_JSON}" <<'PY'
import json, sys, os
with open(sys.argv[1]) as f:
    d = json.load(f)
# outputs.json should be in <module_dir>/outputs.json
module_dir = os.path.dirname(os.path.abspath(sys.argv[1]))
run_dir = os.path.dirname(module_dir)
print(module_dir, run_dir)
PY
)"

# Container path translation: /work/ -> actual repo root
# This is needed because lr_meta runs in a container and writes /work/ paths
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Create a translated outputs.json for R scripts to use
TRANSLATED_OUTPUTS_JSON="${MODULE_DIR}/outputs.host.json"
python3 - "${OUTPUTS_JSON}" "${TRANSLATED_OUTPUTS_JSON}" "${REPO_ROOT}" <<'PY'
import json, sys, os, re

outputs_path = sys.argv[1]
translated_path = sys.argv[2]
repo_root = sys.argv[3]

with open(outputs_path, "r", encoding="utf-8") as f:
    data = json.load(f)

def translate_path(val):
    """Translate /work/ paths to host paths."""
    if isinstance(val, str):
        # Replace /work/ with repo_root
        if val.startswith("/work/"):
            return repo_root + val[5:]  # Remove /work, keep the rest
        return val
    elif isinstance(val, dict):
        return {k: translate_path(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [translate_path(v) for v in val]
    return val

translated = translate_path(data)

with open(translated_path, "w", encoding="utf-8") as f:
    json.dump(translated, f, indent=2, ensure_ascii=False)

print(f"[r_postprocess] Translated container paths (/work/ -> {repo_root})")
PY

# Use translated outputs.json for R scripts
R_OUTPUTS_JSON="${TRANSLATED_OUTPUTS_JSON}"

STEPS_JSON="${MODULE_DIR}/steps.json"

# Standardized output directories (at run_dir level, not module level)
RESULTS_DIR="${RUN_DIR}/results"
RESULTS_PLOTS_DIR="${RESULTS_DIR}/plots"
RESULTS_TABLES_DIR="${RESULTS_DIR}/tables"
RESULTS_VALENCIA_DIR="${RESULTS_DIR}/valencia"
R_POSTPROCESS_LOG_DIR="${MODULE_DIR}/logs/r_postprocess"

mkdir -p "${RESULTS_PLOTS_DIR}" "${RESULTS_TABLES_DIR}" "${RESULTS_VALENCIA_DIR}" "${R_POSTPROCESS_LOG_DIR}"

iso_now() {
  python3 - <<'PY'
from datetime import datetime, timezone, timedelta
tz = timezone(timedelta(hours=10))
print(datetime.now(tz).isoformat(timespec="seconds"))
PY
}

steps_init_if_needed() { local p="$1"; [[ -f "${p}" ]] || printf "[]\n" > "${p}"; }

steps_append() {
  local steps_path="$1" step_name="$2" status="$3" message="$4" tool="$5" cmd="$6" exit_code="$7" started_at="$8" ended_at="$9"
  steps_init_if_needed "${steps_path}"
  python3 - "${steps_path}" "${step_name}" "${status}" "${message}" "${tool}" "${cmd}" "${exit_code}" "${started_at}" "${ended_at}" <<'PY'
import json, sys
path, step_name, status, message, tool, cmd, exit_code, started_at, ended_at = sys.argv[1:]
with open(path, "r", encoding="utf-8") as f:
    arr = json.load(f)
arr.append({
    "step": step_name,
    "status": status,
    "message": message,
    "tool": tool or None,
    "command": cmd or None,
    "exit_code": int(exit_code) if exit_code not in ("", "null") else None,
    "started_at": started_at,
    "ended_at": ended_at,
})
with open(path, "w", encoding="utf-8") as f:
    json.dump(arr, f, ensure_ascii=False, indent=2)
PY
}

jq_get() {
  local file="$1" expr="$2"
  jq -r "${expr} // empty" "${file}" 2>/dev/null || true
}

jq_get_int() {
  local file="$1" expr="$2" default="${3:-0}"
  local v="$(jq -r "${expr} // empty" "${file}" 2>/dev/null || true)"
  if [[ -z "${v}" || "${v}" == "null" ]]; then
    echo "${default}"
  else
    echo "${v}"
  fi
}

# Check if postprocess is enabled
POSTPROCESS_ENABLED="$(jq_get_int "${CONFIG_PATH}" '.postprocess.enabled' '0')"
if [[ "${POSTPROCESS_ENABLED}" != "1" ]]; then
  echo "[r_postprocess] Postprocess disabled by config (postprocess.enabled != 1)"
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "r_postprocess" "skipped" "Postprocess disabled by config (postprocess.enabled != 1)" "" "" "0" "${started}" "${ended}"
  exit 0
fi

# Determine environment context
if [[ "${STABIOM_IN_CONTAINER:-}" == "1" ]]; then
  EXECUTION_ENV="container"
else
  EXECUTION_ENV="host"
fi

# Get Rscript binary - priority: STABIOM_RSCRIPT env > config > command lookup
RSCRIPT_BIN=""
RSCRIPT_SOURCE=""

# 1. Check STABIOM_RSCRIPT environment variable (highest priority)
if [[ -n "${STABIOM_RSCRIPT:-}" ]]; then
  RSCRIPT_BIN="${STABIOM_RSCRIPT}"
  RSCRIPT_SOURCE="STABIOM_RSCRIPT env var"
fi

# 2. Check config setting
if [[ -z "${RSCRIPT_BIN}" ]]; then
  RSCRIPT_BIN="$(jq_get "${CONFIG_PATH}" '.postprocess.rscript_bin')"
  [[ -n "${RSCRIPT_BIN}" ]] && RSCRIPT_SOURCE="config (postprocess.rscript_bin)"
fi

# 3. Fall back to 'Rscript' command
if [[ -z "${RSCRIPT_BIN}" ]]; then
  RSCRIPT_BIN="Rscript"
  RSCRIPT_SOURCE="default"
fi

# Resolve actual path using command -v
RSCRIPT_RESOLVED="$(command -v "${RSCRIPT_BIN}" 2>/dev/null || true)"

# Check if Rscript is available
if [[ -z "${RSCRIPT_RESOLVED}" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"

  echo ""
  echo "================================================================================"
  echo "[r_postprocess] ERROR: Rscript not found"
  echo "================================================================================"
  echo "Environment: ${EXECUTION_ENV}"
  echo "Requested:   ${RSCRIPT_BIN} (source: ${RSCRIPT_SOURCE})"
  echo "PATH:        ${PATH}"
  echo ""
  echo "To fix:"
  echo "  1. Install R: brew install r  (macOS) or apt install r-base (Linux)"
  echo "  2. Or set STABIOM_RSCRIPT=/path/to/Rscript"
  echo "  3. Or set postprocess.rscript_bin in config to absolute path"
  echo "================================================================================"
  echo ""

  steps_append "${STEPS_JSON}" "r_postprocess" "skipped" \
    "Rscript not found (${RSCRIPT_BIN}). Environment: ${EXECUTION_ENV}. Install R or set STABIOM_RSCRIPT env var." \
    "" "" "0" "${started}" "${ended}"

  echo "[r_postprocess] Postprocess skipped (pipeline continues successfully)"
  exit 0
fi

# Use resolved path
RSCRIPT_BIN="${RSCRIPT_RESOLVED}"

echo "[r_postprocess] Environment: ${EXECUTION_ENV}"
echo "[r_postprocess] Rscript: ${RSCRIPT_BIN} (source: ${RSCRIPT_SOURCE})"
echo "[r_postprocess] Module: ${MODULE_NAME}"
echo "[r_postprocess] Outputs JSON: ${OUTPUTS_JSON}"
echo "[r_postprocess] Results dir: ${RESULTS_DIR}"

# Track overall success (step details recorded in steps.json)
STEPS_SUCCEEDED=0

# Helper to run an R script step
# Output type: "plot" or "table"
run_r_step() {
  local step_name="$1"
  local r_script="$2"
  local output_type="${3:-plot}"  # "plot" or "table"

  local step_out_dir
  if [[ "${output_type}" == "plot" ]]; then
    step_out_dir="${RESULTS_PLOTS_DIR}"
  elif [[ "${output_type}" == "table" ]]; then
    step_out_dir="${RESULTS_TABLES_DIR}"
  elif [[ "${output_type}" == "valencia" ]]; then
    step_out_dir="${RESULTS_VALENCIA_DIR}"
  else
    step_out_dir="${RESULTS_PLOTS_DIR}"
  fi

  local step_log="${R_POSTPROCESS_LOG_DIR}/${step_name}.log"

  # Check config for enabled (support both .steps.X.enabled and .steps.X = 1 formats)
  local enabled="$(jq_get_int "${CONFIG_PATH}" ".postprocess.steps.${step_name}.enabled" "$(jq_get_int "${CONFIG_PATH}" ".postprocess.steps.${step_name}" '0')")"

  if [[ "${enabled}" != "1" ]]; then
    echo "[r_postprocess] ${step_name}: skipped (not enabled)"
    return 0
  fi

  if [[ ! -f "${r_script}" ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "r_postprocess_${step_name}" "failed" "R script not found: ${r_script}" "${RSCRIPT_BIN}" "Rscript" "2" "${started}" "${ended}"
    echo "[r_postprocess] ${step_name}: FAILED (R script not found)"
    return 1
  fi

  mkdir -p "${step_out_dir}"

  # Get params as JSON string
  local params_json="$(jq -c ".postprocess.steps.${step_name}.params // {}" "${CONFIG_PATH}" 2>/dev/null || echo '{}')"

  echo "[r_postprocess] ${step_name}: running..."

  started="$(iso_now)"
  set +e
  "${RSCRIPT_BIN}" "${r_script}" \
    --outputs_json "${R_OUTPUTS_JSON}" \
    --out_dir "${step_out_dir}" \
    --params_json "${params_json}" \
    --module "${MODULE_NAME}" \
    >"${step_log}" 2>&1
  ec=$?
  set -e
  ended="$(iso_now)"

  if [[ $ec -ne 0 ]]; then
    steps_append "${STEPS_JSON}" "r_postprocess_${step_name}" "failed" "R script failed (see logs/r_postprocess/${step_name}.log)" "${RSCRIPT_BIN}" "Rscript ${step_name}.R" "${ec}" "${started}" "${ended}"
    echo "[r_postprocess] ${step_name}: FAILED (exit code ${ec})"
    # Show first few lines of error
    head -20 "${step_log}" 2>/dev/null || true
    return 1
  fi

  steps_append "${STEPS_JSON}" "r_postprocess_${step_name}" "succeeded" "R postprocess step completed" "${RSCRIPT_BIN}" "Rscript ${step_name}.R" "0" "${started}" "${ended}"
  STEPS_SUCCEEDED=$((STEPS_SUCCEEDED + 1))
  echo "[r_postprocess] ${step_name}: succeeded"
  return 0
}

# Track overall status
OVERALL_EC=0

# Run each step with appropriate output type
run_r_step "heatmap" "${SCRIPT_DIR}/heatmap.R" "plot" || OVERALL_EC=1
run_r_step "piechart" "${SCRIPT_DIR}/piechart.R" "plot" || OVERALL_EC=1
run_r_step "stacked_bar" "${SCRIPT_DIR}/stacked_bar.R" "plot" || OVERALL_EC=1
run_r_step "relative_abundance" "${SCRIPT_DIR}/relative_abundance.R" "plot" || OVERALL_EC=1
run_r_step "results_csv" "${SCRIPT_DIR}/results_csv.R" "table" || OVERALL_EC=1

# Valencia step: only run if valencia outputs exist
VALENCIA_ENABLED="$(jq_get_int "${CONFIG_PATH}" '.postprocess.steps.valencia.enabled' "$(jq_get_int "${CONFIG_PATH}" '.postprocess.steps.valencia' '0')")"
if [[ "${VALENCIA_ENABLED}" == "1" ]]; then
  # Check if valencia outputs exist in outputs.json
  HAS_VALENCIA="$(python3 - "${R_OUTPUTS_JSON}" "${MODULE_DIR}" <<'PY'
import json, sys, os
outputs_path = sys.argv[1]
module_dir = sys.argv[2]

with open(outputs_path) as f:
    d = json.load(f)

# Check for valencia section (supports multiple key names)
for key in ["valencia", "valencia_results"]:
    v = d.get(key, {})
    if v:
        if isinstance(v, dict) and (v.get("output_csv") or v.get("dir") or v.get("assignments_csv")):
            print("1")
            sys.exit(0)
        elif isinstance(v, str) and os.path.exists(v):
            print("1")
            sys.exit(0)

# Also check for final/valencia directory
final_valencia = os.path.join(module_dir, "final", "valencia")
if os.path.isdir(final_valencia) and any(os.scandir(final_valencia)):
    print("1")
    sys.exit(0)

print("0")
PY
)"

  if [[ "${HAS_VALENCIA}" == "1" ]]; then
    run_r_step "valencia" "${SCRIPT_DIR}/valencia.R" "valencia" || OVERALL_EC=1
  else
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "r_postprocess_valencia" "skipped" "VALENCIA outputs not found in this run" "" "" "0" "${started}" "${ended}"
    echo "[r_postprocess] valencia: skipped (no valencia outputs in this run)"
  fi
else
  echo "[r_postprocess] valencia: skipped (not enabled)"
fi

# Copy existing module outputs to standardized location
echo "[r_postprocess] Consolidating outputs to results/"

# Sync generated plots from results/plots/ back to module final/plots/
# This ensures final/plots/ is populated for consumers who expect the legacy location
FINAL_DIR="${MODULE_DIR}/final"
FINAL_PLOTS_DIR="${FINAL_DIR}/plots"
if [[ -d "${RESULTS_PLOTS_DIR}" ]]; then
  mkdir -p "${FINAL_PLOTS_DIR}"
  shopt -s nullglob
  plot_files=( "${RESULTS_PLOTS_DIR}"/*.png "${RESULTS_PLOTS_DIR}"/*.pdf "${RESULTS_PLOTS_DIR}"/*.csv )
  shopt -u nullglob
  # Guard against empty array under set -u
  if [[ ${#plot_files[@]} -gt 0 ]]; then
    for pf in "${plot_files[@]}"; do
      cp -f "${pf}" "${FINAL_PLOTS_DIR}/"
      echo "[r_postprocess] Synced $(basename "${pf}") to final/plots/"
    done
    echo "[r_postprocess] Synced ${#plot_files[@]} plot file(s) to final/plots/"
  else
    echo "[r_postprocess] No plot files found in results/plots/ to sync to final/"
  fi
else
  echo "[r_postprocess] results/plots/ not found, skipping sync to final/"
fi

# Copy tidy CSVs from module postprocess if they exist
python3 - "${R_OUTPUTS_JSON}" "${RESULTS_TABLES_DIR}" "${RESULTS_VALENCIA_DIR}" "${MODULE_DIR}" <<'PY'
import json, sys, os, shutil
from pathlib import Path

outputs_path = sys.argv[1]
tables_dir = Path(sys.argv[2])
valencia_dir = Path(sys.argv[3])
module_dir = Path(sys.argv[4])

with open(outputs_path) as f:
    outputs = json.load(f)

# Copy tidy CSVs if they exist
postprocess = outputs.get("postprocess", {})
postprocess_dir = postprocess.get("dir")
if postprocess_dir and os.path.isdir(postprocess_dir):
    for csv_name in ["kraken_species_tidy.csv", "kraken_genus_tidy.csv"]:
        src = os.path.join(postprocess_dir, csv_name)
        if os.path.exists(src):
            dst = tables_dir / csv_name
            shutil.copy2(src, dst)
            print(f"[r_postprocess] Copied {csv_name} to results/tables/")

# Copy kraken reports if they exist
for key in ["kraken2", "taxonomy"]:
    section = outputs.get(key, {})
    if isinstance(section, dict):
        for k, v in section.items():
            if isinstance(v, str) and v.endswith(".kreport") and os.path.exists(v):
                dst = tables_dir / os.path.basename(v)
                shutil.copy2(v, dst)
                print(f"[r_postprocess] Copied {os.path.basename(v)} to results/tables/")

# Copy valencia outputs if they exist (check multiple key names)
for valencia_key in ["valencia", "valencia_results"]:
    valencia = outputs.get(valencia_key, {})
    if valencia:
        valencia_src_dir = None
        if isinstance(valencia, dict):
            valencia_src_dir = valencia.get("dir")
        elif isinstance(valencia, str):
            valencia_src_dir = valencia if os.path.isdir(valencia) else os.path.dirname(valencia)

        if valencia_src_dir and os.path.isdir(valencia_src_dir):
            for f in Path(valencia_src_dir).glob("*"):
                if f.is_file():
                    dst = valencia_dir / f.name
                    if not dst.exists():
                        shutil.copy2(f, dst)
                        print(f"[r_postprocess] Copied valencia/{f.name} to results/valencia/")

# Also check final/ directory for legacy outputs
final_dir = module_dir / "final"
if final_dir.exists():
    # Copy tables
    final_tables = final_dir / "tables"
    if final_tables.exists():
        for f in final_tables.glob("*"):
            if f.is_file():
                dst = tables_dir / f.name
                if not dst.exists():
                    shutil.copy2(f, dst)
                    print(f"[r_postprocess] Copied final/tables/{f.name} to results/tables/")

    # Copy valencia from final if not already copied
    final_valencia = final_dir / "valencia"
    if final_valencia.exists():
        for f in final_valencia.glob("*"):
            if f.is_file():
                dst = valencia_dir / f.name
                if not dst.exists():
                    shutil.copy2(f, dst)
                    print(f"[r_postprocess] Copied final/valencia/{f.name} to results/valencia/")
PY

# Write manifest.json
python3 - "${RESULTS_DIR}" "${MODULE_NAME}" "${R_OUTPUTS_JSON}" <<'PY'
import json, sys, os
from pathlib import Path

results_dir = Path(sys.argv[1])
module_name = sys.argv[2]
outputs_json_path = sys.argv[3]

plots_dir = results_dir / "plots"
tables_dir = results_dir / "tables"
valencia_dir = results_dir / "valencia"

# Collect files
plots = sorted([f.name for f in plots_dir.glob("*") if f.is_file()]) if plots_dir.exists() else []
tables = sorted([f.name for f in tables_dir.glob("*") if f.is_file()]) if tables_dir.exists() else []
valencia = sorted([f.name for f in valencia_dir.glob("*") if f.is_file()]) if valencia_dir.exists() else []

# Load run_name from outputs.json if available
run_name = ""
try:
    with open(outputs_json_path) as f:
        outputs = json.load(f)
        run_name = outputs.get("run_name", outputs.get("run_id", ""))
except:
    pass

manifest = {
    "module": module_name,
    "run_name": run_name,
    "postprocess_type": "r",
    "outputs": {
        "plots": plots,
        "tables": tables,
        "valencia": valencia
    },
    "summary": {
        "plots_count": len(plots),
        "tables_count": len(tables),
        "valencia_count": len(valencia),
        "has_kraken2": any("kraken" in t.lower() or "kreport" in t.lower() for t in tables),
        "has_valencia": len(valencia) > 0
    }
}

manifest_path = results_dir / "manifest.json"
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)

print(f"[r_postprocess] Wrote manifest: {manifest_path}")
print(f"[r_postprocess] Summary: {len(plots)} plots, {len(tables)} tables, {len(valencia)} valencia files")
PY

# Update final/manifest.json to include synced plots
# This ensures consumers looking at final/manifest.json see the correct plot count
python3 - "${MODULE_DIR}" "${R_OUTPUTS_JSON}" <<'PY'
import json, sys, os
from pathlib import Path

module_dir = Path(sys.argv[1])
outputs_json_path = sys.argv[2]

final_dir = module_dir / "final"
final_manifest_path = final_dir / "manifest.json"

if not final_dir.exists():
    print("[r_postprocess] No final/ directory, skipping final/manifest.json update")
    sys.exit(0)

# Load existing manifest or create new one
manifest = {}
if final_manifest_path.exists():
    try:
        with open(final_manifest_path) as f:
            manifest = json.load(f)
    except:
        pass

# Scan final/plots, final/tables, final/valencia
plots_dir = final_dir / "plots"
tables_dir = final_dir / "tables"
valencia_dir = final_dir / "valencia"

plots = sorted([f.name for f in plots_dir.glob("*") if f.is_file()]) if plots_dir.exists() else []
tables = sorted([f.name for f in tables_dir.glob("*") if f.is_file()]) if tables_dir.exists() else []
valencia = sorted([f.name for f in valencia_dir.glob("*") if f.is_file()]) if valencia_dir.exists() else []

# Load run_name from outputs.json if not in manifest
if not manifest.get("run_name"):
    try:
        with open(outputs_json_path) as f:
            outputs = json.load(f)
            manifest["run_name"] = outputs.get("run_name", outputs.get("run_id", ""))
    except:
        pass

# Update manifest
manifest["outputs"] = {
    "tables": tables,
    "plots": plots,
    "valencia": valencia
}

with open(final_manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)

print(f"[r_postprocess] Updated final/manifest.json: {len(plots)} plots, {len(tables)} tables, {len(valencia)} valencia")
PY

# Update outputs.json with r_postprocess info
tmp="${OUTPUTS_JSON}.tmp"
python3 - "${OUTPUTS_JSON}" "${tmp}" "${RESULTS_DIR}" "${R_POSTPROCESS_LOG_DIR}" <<'PY'
import json, sys, os

outputs_path = sys.argv[1]
tmp_path = sys.argv[2]
results_dir = sys.argv[3]
log_dir = sys.argv[4]

with open(outputs_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# Add r_postprocess section
data["r_postprocess"] = {
    "results_dir": results_dir,
    "plots_dir": os.path.join(results_dir, "plots"),
    "tables_dir": os.path.join(results_dir, "tables"),
    "valencia_dir": os.path.join(results_dir, "valencia"),
    "manifest": os.path.join(results_dir, "manifest.json"),
    "log_dir": log_dir
}

with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
mv "${tmp}" "${OUTPUTS_JSON}"

# Record overall postprocess status
started="$(iso_now)"; ended="$(iso_now)"
if [[ "${OVERALL_EC}" -eq 0 ]]; then
  steps_append "${STEPS_JSON}" "r_postprocess" "succeeded" "R postprocessing completed successfully" "" "" "0" "${started}" "${ended}"
else
  steps_append "${STEPS_JSON}" "r_postprocess" "completed_with_errors" "R postprocessing completed with some step failures" "" "" "${OVERALL_EC}" "${started}" "${ended}"
fi

echo "[r_postprocess] Complete. Results: ${RESULTS_DIR}"
exit ${OVERALL_EC}
