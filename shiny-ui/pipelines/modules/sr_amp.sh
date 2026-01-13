#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="sr_amp"

usage() { echo "Usage: $0 --config <effective_config.json>"; }

CONFIG_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${CONFIG_PATH}" ]]; then echo "ERROR: --config is required" >&2; usage; exit 2; fi
if [[ ! -f "${CONFIG_PATH}" ]]; then echo "ERROR: Config not found: ${CONFIG_PATH}" >&2; exit 2; fi
if ! command -v jq >/dev/null 2>&1; then echo "ERROR: jq is required but not found in PATH" >&2; exit 2; fi
if ! command -v python3 >/dev/null 2>&1; then echo "ERROR: python3 is required but not found in PATH" >&2; exit 2; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINES_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS_SH="${PIPELINES_DIR}/tools.sh"
if [[ ! -f "${TOOLS_SH}" ]]; then echo "ERROR: Missing shared tools file: ${TOOLS_SH}" >&2; exit 2; fi
# shellcheck disable=SC1090
source "${TOOLS_SH}"

jq_first() {
  local file="$1"; shift
  local v=""
  for expr in "$@"; do
    v="$(jq -er "${expr} // empty" "${file}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      echo "${v}"
      return 0
    fi
  done
  return 1
}

jq_first_int() {
  local file="$1"; shift
  local v=""
  for expr in "$@"; do
    v="$(jq -er "${expr} // empty" "${file}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" && "${v}" =~ ^-?[0-9]+$ ]]; then
      echo "${v}"
      return 0
    fi
  done
  return 1
}

require_file() {
  local p="$1"
  [[ -n "${p}" && "${p}" != "null" ]] || { echo "ERROR: Required file path is empty" >&2; exit 2; }
  [[ -f "${p}" ]] || { echo "ERROR: File not found: ${p}" >&2; exit 2; }
}

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

print_step_status() {
  local steps_path="$1"
  local step="$2"
  if [[ ! -f "${steps_path}" ]]; then
    echo "[${MODULE_NAME}] ${step}: no steps.json"
    return 0
  fi
  python3 - "${steps_path}" "${step}" "${MODULE_NAME}" <<'PY'
import json, sys
path, step, module = sys.argv[1:]
with open(path, "r", encoding="utf-8") as f:
    arr = json.load(f)
found = [x for x in arr if x.get("step")==step]
if not found:
    print(f"[{module}] {step}: not recorded")
    raise SystemExit(0)
x = found[-1]
print(f"[{module}] {step}: {x.get('status','')} - {x.get('message','')}")
PY
}

count_fastq_lines() {
  local p="${1:-}"
  if [[ -z "${p}" || "${p}" == "null" ]]; then echo "0"; return 0; fi
  require_file "${p}"
  if [[ "${p}" == *.gz ]]; then
    (gzip -cd "${p}" | wc -l 2>/dev/null || true) | tr -cd '0-9'
  else
    (wc -l < "${p}" 2>/dev/null || true) | tr -cd '0-9'
  fi
}

estimate_reads_from_lines() {
  local lines="${1:-0}"
  python3 - "$lines" <<'PY'
import sys
s = sys.argv[1]
s = "".join([c for c in s if c.isdigit()]) or "0"
lines = int(s)
print(lines // 4)
PY
}

derive_canonical_barcode_id() {
  local a="${1:-}"
  local b="${2:-}"
  python3 - "$a" "$b" <<'PY'
import re, sys
a = sys.argv[1] or ""
b = sys.argv[2] or ""
bc_re = re.compile(r'(barcode|bc)[\s_\-]*0*([0-9]{1,3})', re.IGNORECASE)
def find_id(s: str):
    m = bc_re.search(s or "")
    if not m:
        return None
    n = int(m.group(2))
    return f"barcode{n:02d}"
sid = find_id(a) or find_id(b)
print(sid or "")
PY
}

# -----------------------------
# Read config + validate
# -----------------------------
INPUT_STYLE="$(jq_first "${CONFIG_PATH}" '.input.style' '.inputs.style' '.input_style' '.inputs.input_style' || true)"
[[ -n "${INPUT_STYLE}" ]] || INPUT_STYLE="FASTQ_PAIRED"

if [[ "${INPUT_STYLE}" != "FASTQ_PAIRED" && "${INPUT_STYLE}" != "FASTQ_SINGLE" ]]; then
  echo "ERROR: ${MODULE_NAME} expects FASTQ_PAIRED or FASTQ_SINGLE, got: ${INPUT_STYLE}" >&2
  exit 2
fi

OUTPUT_DIR="$(jq_first "${CONFIG_PATH}" '.run_dir' '.run.run_dir' '.run.work_dir' '.output_dir' '.run.output_dir' '.outputs.output_dir' '.output.output_dir' || true)"
[[ -n "${OUTPUT_DIR}" ]] || { echo "ERROR: Could not determine output dir from config" >&2; exit 2; }
mkdir -p "${OUTPUT_DIR}"

RUN_ID="$(jq_first "${CONFIG_PATH}" '.run_id_resolved' '.run.run_id' '.run_id' '.id' '.run.id' || true)"
PIPELINE_ID="$(jq_first "${CONFIG_PATH}" '.pipeline_id' '.run.pipeline_id' '.pipeline.id' '.pipeline_key' || true)"

SAMPLE_ID="$(jq_first "${CONFIG_PATH}" '.qiime2.sample_id' '.sample_id' || true)"
[[ -n "${SAMPLE_ID}" ]] || SAMPLE_ID="barcode01"
if [[ "${SAMPLE_ID}" == "sample1" ]]; then SAMPLE_ID="barcode01"; fi

FASTQ_R1_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq_r1' '.inputs.fastq_r1' '.input.r1' '.inputs.r1' '.input.read1' '.inputs.read1' || true)"
FASTQ_R2_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq_r2' '.inputs.fastq_r2' '.input.r2' '.inputs.r2' '.input.read2' '.inputs.read2' || true)"

if [[ -z "${FASTQ_R1_SRC}" ]]; then
  echo "ERROR: ${INPUT_STYLE} requires input.fastq_r1 in config." >&2
  exit 2
fi
require_file "${FASTQ_R1_SRC}"

if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  [[ -n "${FASTQ_R2_SRC}" ]] || { echo "ERROR: FASTQ_PAIRED requires input.fastq_r2 in config." >&2; exit 2; }
  require_file "${FASTQ_R2_SRC}"
else
  FASTQ_R2_SRC=""
fi

PRIMER_FWD="$(jq_first "${CONFIG_PATH}" '.qiime2.primers.forward' || true)"
PRIMER_REV="$(jq_first "${CONFIG_PATH}" '.qiime2.primers.reverse' || true)"

CLASSIFIER_QZA_HOST="$(jq_first "${CONFIG_PATH}" '.qiime2.classifier.qza' || true)"
META_TSV_HOST="$(jq_first "${CONFIG_PATH}" '.qiime2.diversity.metadata_tsv' '.qiime2.metadata_tsv' || true)"
SAMPLING_DEPTH="$(jq_first_int "${CONFIG_PATH}" '.qiime2.diversity.sampling_depth' || true)"

DADA2_TRIM_LEFT_F="$(jq_first_int "${CONFIG_PATH}" '.qiime2.dada2.trim_left_f' || true)"
DADA2_TRIM_LEFT_R="$(jq_first_int "${CONFIG_PATH}" '.qiime2.dada2.trim_left_r' || true)"
DADA2_TRUNC_LEN_F="$(jq_first_int "${CONFIG_PATH}" '.qiime2.dada2.trunc_len_f' || true)"
DADA2_TRUNC_LEN_R="$(jq_first_int "${CONFIG_PATH}" '.qiime2.dada2.trunc_len_r' || true)"
DADA2_N_THREADS="$(jq_first_int "${CONFIG_PATH}" '.qiime2.dada2.n_threads' || true)"

SPECIMEN="$(jq_first "${CONFIG_PATH}" '.specimen' '.params.common.specimen' || true)"
[[ -n "${SPECIMEN}" ]] || SPECIMEN="other"

VALENCIA_MODE="$(jq_first "${CONFIG_PATH}" '.valencia.mode' || true)"
[[ -n "${VALENCIA_MODE}" ]] || VALENCIA_MODE="auto"

VALENCIA_CENTROIDS_HOST="$(jq_first "${CONFIG_PATH}" '.valencia.centroids_csv' '.valencia.centroids_path' '.valencia.centroids' || true)"

VALENCIA_SHOULD_RUN="0"
if [[ "${VALENCIA_MODE}" == "on" ]]; then
  VALENCIA_SHOULD_RUN="1"
elif [[ "${VALENCIA_MODE}" == "auto" && "${SPECIMEN}" == "vaginal" ]]; then
  VALENCIA_SHOULD_RUN="1"
fi

# -----------------------------
# Layout: <run_dir>/sr_amp/...
# -----------------------------
MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
FASTQ_STAGE_DIR="${MODULE_OUT_DIR}/inputs/fastq"
REF_STAGE_DIR="${MODULE_OUT_DIR}/inputs/reference"
META_STAGE_DIR="${MODULE_OUT_DIR}/inputs/metadata"
RESULTS_DIR="${MODULE_OUT_DIR}/results"
LOGS_DIR="${MODULE_OUT_DIR}/logs"
STEPS_JSON="${MODULE_OUT_DIR}/steps.json"

mkdir -p "${FASTQ_STAGE_DIR}" "${REF_STAGE_DIR}" "${META_STAGE_DIR}" "${RESULTS_DIR}" "${LOGS_DIR}"

echo "[${MODULE_NAME}] config: ${CONFIG_PATH}"
echo "[${MODULE_NAME}] output_dir: ${OUTPUT_DIR}"
echo "[${MODULE_NAME}] module_out_dir: ${MODULE_OUT_DIR}"
echo "[${MODULE_NAME}] input_style: ${INPUT_STYLE}"

# Stage FASTQs
STAGED_R1="${FASTQ_STAGE_DIR}/$(basename "${FASTQ_R1_SRC}")"
STAGED_R2=""
rm -f "${STAGED_R1}"
cp -f "${FASTQ_R1_SRC}" "${STAGED_R1}"

if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  STAGED_R2="${FASTQ_STAGE_DIR}/$(basename "${FASTQ_R2_SRC}")"
  rm -f "${STAGED_R2}"
  cp -f "${FASTQ_R2_SRC}" "${STAGED_R2}"
fi

DERIVED_BC_ID="$(derive_canonical_barcode_id "${STAGED_R1}" "${STAGED_R2}")"
if [[ -n "${DERIVED_BC_ID}" ]]; then
  SAMPLE_ID="${DERIVED_BC_ID}"
else
  FALLBACK_ID="$(python3 - "$(basename "${STAGED_R1}")" <<'PY'
import re, sys
name = sys.argv[1]
name = re.sub(r'\.f(ast)?q(\.gz)?$', '', name, flags=re.IGNORECASE)
name = re.sub(r'(_R?1|_1)$', '', name)
print(name)
PY
)"
  [[ -n "${FALLBACK_ID}" ]] && SAMPLE_ID="${FALLBACK_ID}"
fi

# Stage classifier / metadata / valencia centroids if provided
STAGED_CLASSIFIER=""
if [[ -n "${CLASSIFIER_QZA_HOST}" ]]; then
  CLASSIFIER_QZA_HOST="$(printf "%s" "${CLASSIFIER_QZA_HOST}" | tr -d '\r\n')"
  require_file "${CLASSIFIER_QZA_HOST}"
  STAGED_CLASSIFIER="${REF_STAGE_DIR}/$(basename "${CLASSIFIER_QZA_HOST}")"
  rm -f "${STAGED_CLASSIFIER}"
  cp -f "${CLASSIFIER_QZA_HOST}" "${STAGED_CLASSIFIER}"
fi

STAGED_VALENCIA_CENTROIDS=""
if [[ -n "${VALENCIA_CENTROIDS_HOST}" ]]; then
  VALENCIA_CENTROIDS_HOST="$(printf "%s" "${VALENCIA_CENTROIDS_HOST}" | tr -d '\r\n')"
  require_file "${VALENCIA_CENTROIDS_HOST}"
  STAGED_VALENCIA_CENTROIDS="${REF_STAGE_DIR}/$(basename "${VALENCIA_CENTROIDS_HOST}")"
  rm -f "${STAGED_VALENCIA_CENTROIDS}"
  cp -f "${VALENCIA_CENTROIDS_HOST}" "${STAGED_VALENCIA_CENTROIDS}"
fi

STAGED_META=""
if [[ -n "${META_TSV_HOST}" ]]; then
  META_TSV_HOST="$(printf "%s" "${META_TSV_HOST}" | tr -d '\r\n')"
  require_file "${META_TSV_HOST}"
  STAGED_META="${META_STAGE_DIR}/$(basename "${META_TSV_HOST}")"
  rm -f "${STAGED_META}"
  cp -f "${META_TSV_HOST}" "${STAGED_META}"
fi

# Normalize metadata IDs (optional)
STAGED_META_NORMALIZED=""
META_NORMALIZE_LOG="${LOGS_DIR}/metadata_normalize.log"

if [[ -n "${STAGED_META}" ]]; then
  STAGED_META_NORMALIZED="${META_STAGE_DIR}/metadata.normalized.tsv"
  started="$(iso_now)"
  set +e
  python3 - "${STAGED_META}" "${STAGED_META_NORMALIZED}" "${SAMPLE_ID}" >"${META_NORMALIZE_LOG}" 2>&1 <<'PY'
import sys, re
src, dst, want_id = sys.argv[1:]
want_id = (want_id or "").strip()
bc_re = re.compile(r'(barcode|bc)[\s_\-]*0*([0-9]{1,3})', re.IGNORECASE)
def canon_id(s: str) -> str:
    s = (s or "").strip()
    m = bc_re.search(s)
    if not m:
        return s
    n = int(m.group(2))
    return f"barcode{n:02d}"
lines = []
with open(src, "r", encoding="utf-8", errors="replace") as f:
    lines = f.read().splitlines()
if not lines:
    raise SystemExit("ERROR: metadata file is empty")
preamble = []
idx = 0
while idx < len(lines) and lines[idx].startswith("#"):
    preamble.append(lines[idx]); idx += 1
if idx >= len(lines):
    raise SystemExit("ERROR: metadata file has no header row")
header = lines[idx]; idx += 1
delim = "\t" if "\t" in header else ","
hdr = header.split(delim)
sid_col = None
for i, c in enumerate(hdr):
    if c.strip().lower() == "sample-id":
        sid_col = i; break
if sid_col is None:
    sid_col = 0
    hdr[0] = "sample-id"
rows = []
seen = set()
for j in range(idx, len(lines)):
    ln = lines[j]
    if not ln.strip() or ln.lstrip().startswith("#"):
        continue
    parts = ln.split(delim)
    if len(parts) < len(hdr):
        parts = parts + [""] * (len(hdr) - len(parts))
    old = parts[sid_col].strip()
    new = canon_id(old)
    parts[sid_col] = new
    rows.append(parts)
    seen.add(new)
want_canon = canon_id(want_id)
if want_canon and want_canon not in seen:
    blank = [""] * len(hdr)
    blank[sid_col] = want_canon
    rows.append(blank)
with open(dst, "w", encoding="utf-8", newline="") as out:
    for ln in preamble:
        out.write(ln + "\n")
    out.write(delim.join(hdr) + "\n")
    for r in rows:
        out.write(delim.join(r) + "\n")
print(f"OK: normalized metadata IDs -> {dst}")
print(f"OK: ensured sample-id present -> {want_canon}")
PY
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "metadata_normalize" "succeeded" "Normalized metadata sample IDs (see logs/metadata_normalize.log)" "python3" "python3 normalize_metadata" "0" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "metadata_normalize" "failed" "Metadata normalization failed (see logs/metadata_normalize.log)" "python3" "python3 normalize_metadata" "${ec}" "${started}" "${ended}"
    echo "ERROR: Failed to normalize metadata for QIIME2. See: ${META_NORMALIZE_LOG}" >&2
    exit 2
  fi
fi

# -----------------------------
# outputs.json base + metrics
# -----------------------------
OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"
jq -n \
  --arg mod "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg sample_id "${SAMPLE_ID}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg fastq_r1 "${STAGED_R1}" \
  --arg fastq_r2 "${STAGED_R2}" \
  --arg classifier_qza "${STAGED_CLASSIFIER}" \
  --arg metadata_tsv "${STAGED_META}" \
  --arg metadata_tsv_normalized "${STAGED_META_NORMALIZED}" \
  --arg valencia_centroids "${STAGED_VALENCIA_CENTROIDS}" \
  '{
    module_name: $mod,
    pipeline_id: $pipeline_id,
    run_id: $run_id,
    sample_id: $sample_id,
    input_style: $input_style,
    inputs: {
      fastq_r1: $fastq_r1,
      fastq_r2: ($fastq_r2 | select(length>0) // null)
    },
    reference: {
      classifier_qza: ($classifier_qza | select(length>0) // null),
      valencia_centroids: ($valencia_centroids | select(length>0) // null)
    },
    metadata: {
      metadata_tsv: ($metadata_tsv | select(length>0) // null),
      metadata_tsv_normalized: ($metadata_tsv_normalized | select(length>0) // null)
    }
  }' > "${OUTPUTS_JSON}"

METRICS_JSON="${MODULE_OUT_DIR}/metrics.json"
R1_LINES="$(count_fastq_lines "${STAGED_R1}")"
R2_LINES="$(count_fastq_lines "${STAGED_R2}")"
[[ -n "${R1_LINES}" ]] || R1_LINES="0"
[[ -n "${R2_LINES}" ]] || R2_LINES="0"
R1_READS="$(estimate_reads_from_lines "${R1_LINES}")"
R2_READS="$(estimate_reads_from_lines "${R2_LINES}")"

jq -n \
  --arg mod "${MODULE_NAME}" \
  --arg fastq_r1 "${STAGED_R1}" \
  --arg fastq_r2 "${STAGED_R2}" \
  --argjson r1_lines "${R1_LINES}" \
  --argjson r2_lines "${R2_LINES}" \
  --argjson r1_reads_estimate "${R1_READS}" \
  --argjson r2_reads_estimate "${R2_READS}" \
  '{
    module_name: $mod,
    fastq_r1: $fastq_r1,
    fastq_r2: ($fastq_r2 | select(length>0) // null),
    r1_lines: $r1_lines,
    r2_lines: $r2_lines,
    r1_reads_estimate: $r1_reads_estimate,
    r2_reads_estimate: $r2_reads_estimate
  }' > "${METRICS_JSON}"

tmp="${OUTPUTS_JSON}.tmp"
jq --arg metrics_path "${METRICS_JSON}" --slurpfile metrics "${METRICS_JSON}" '. + {metrics_path:$metrics_path, metrics:$metrics[0]}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# FastQC + MultiQC (optional)
# -----------------------------
FASTQC_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.fastqc_bin' 'fastqc')"
FASTQC_OUTDIR="${RESULTS_DIR}/fastqc"
FASTQC_LOG="${LOGS_DIR}/fastqc.log"

if [[ -z "${FASTQC_BIN}" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "fastqc" "skipped" "fastqc not found (install fastqc or set tools.fastqc_bin)" "" "" "0" "${started}" "${ended}"
else
  mkdir -p "${FASTQC_OUTDIR}"
  started="$(iso_now)"
  set +e
  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    "${FASTQC_BIN}" -o "${FASTQC_OUTDIR}" "${STAGED_R1}" "${STAGED_R2}" >"${FASTQC_LOG}" 2>&1
  else
    "${FASTQC_BIN}" -o "${FASTQC_OUTDIR}" "${STAGED_R1}" >"${FASTQC_LOG}" 2>&1
  fi
  ec=$?
  set -e
  ended="$(iso_now)"

  if exit_code_means_tool_missing "${ec}"; then
    steps_append "${STEPS_JSON}" "fastqc" "skipped" "fastqc command not found at runtime (check tools.fastqc_bin / PATH)" "${FASTQC_BIN}" "fastqc" "${ec}" "${started}" "${ended}"
  elif [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "fastqc" "succeeded" "fastqc completed" "${FASTQC_BIN}" "fastqc" "0" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "fastqc" "failed" "fastqc failed (see logs/fastqc.log)" "${FASTQC_BIN}" "fastqc" "${ec}" "${started}" "${ended}"
  fi
fi

MULTIQC_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.multiqc_bin' 'multiqc')"
MULTIQC_LOG="${LOGS_DIR}/multiqc.log"
MULTIQC_OUTDIR="${RESULTS_DIR}/multiqc"

if [[ -z "${MULTIQC_BIN}" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "multiqc" "skipped" "multiqc not found (install multiqc or set tools.multiqc_bin)" "" "" "0" "${started}" "${ended}"
else
  mkdir -p "${MULTIQC_OUTDIR}"
  started="$(iso_now)"
  set +e
  "${MULTIQC_BIN}" -o "${MULTIQC_OUTDIR}" "${RESULTS_DIR}" >"${MULTIQC_LOG}" 2>&1
  ec=$?
  set -e
  ended="$(iso_now)"

  if exit_code_means_tool_missing "${ec}"; then
    steps_append "${STEPS_JSON}" "multiqc" "skipped" "multiqc command not found at runtime (check tools.multiqc_bin / PATH)" "${MULTIQC_BIN}" "multiqc" "${ec}" "${started}" "${ended}"
  elif [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "multiqc" "succeeded" "multiqc completed" "${MULTIQC_BIN}" "multiqc" "0" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "multiqc" "failed" "multiqc failed (see logs/multiqc.log)" "${MULTIQC_BIN}" "multiqc" "${ec}" "${started}" "${ended}"
  fi
fi

MULTIQC_REPORT="${MULTIQC_OUTDIR}/multiqc_report.html"
tmp="${OUTPUTS_JSON}.tmp"
jq --arg steps_path "${STEPS_JSON}" \
   --arg multiqc_dir "${MULTIQC_OUTDIR}" \
   --arg multiqc_report_html "${MULTIQC_REPORT}" \
   '. + {steps_path:$steps_path, multiqc_dir:$multiqc_dir, multiqc_report_html:$multiqc_report_html}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# QIIME2 (docker) - NO bash inside container
# -----------------------------
if ! command -v docker >/dev/null 2>&1; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "qiime2" "failed" "docker not available; cannot run QIIME2" "docker" "docker" "3" "${started}" "${ended}"
  exit 3
fi

QIIME2_IMAGE="quay.io/qiime2/amplicon:2024.10"
QIIME2_DIR="${RESULTS_DIR}/qiime2"
QIIME2_LOG="${LOGS_DIR}/qiime2.log"
QIIME2_TMP_DIR="${QIIME2_DIR}/tmp"
mkdir -p "${QIIME2_DIR}" "${QIIME2_TMP_DIR}"

OUTPUT_DIR_HOST="${OUTPUT_DIR}"

qiime2_docker_base=(
  docker run --rm --platform=linux/amd64
  -v "${OUTPUT_DIR_HOST}:/run:rw"
  "${QIIME2_IMAGE}"
)

qiime2_run() {
  local step="$1"; shift
  local started ended ec
  started="$(iso_now)"

  {
    echo
    echo "[qiime2] step=${step}"
    printf "[qiime2] cmd: "
    printf "%q " "${qiime2_docker_base[@]}" "$@"
    echo
  } >>"${QIIME2_LOG}"

  set +e
  "${qiime2_docker_base[@]}" "$@" >>"${QIIME2_LOG}" 2>&1
  ec=$?
  set -e

  ended="$(iso_now)"

  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "${step}" "succeeded" "${step} completed" "docker" "docker run ${QIIME2_IMAGE} $*" "0" "${started}" "${ended}"
    return 0
  fi

  steps_append "${STEPS_JSON}" "${step}" "failed" "${step} failed (see logs/qiime2.log and results/qiime2/tmp)" "docker" "docker run ${QIIME2_IMAGE} $*" "${ec}" "${started}" "${ended}"
  return "${ec}"
}

# sanity check: qiime must be invoked directly (not via shell)
started="$(iso_now)"
set +e
"${qiime2_docker_base[@]}" qiime --version >"${QIIME2_LOG}" 2>&1
ec=$?
set -e
ended="$(iso_now)"
if [[ $ec -ne 0 ]]; then
  steps_append "${STEPS_JSON}" "qiime2_version" "failed" "QIIME2 image failed to run qiime --version (see logs/qiime2.log)" "docker" "docker run ${QIIME2_IMAGE} qiime --version" "${ec}" "${started}" "${ended}"
  exit 3
else
  steps_append "${STEPS_JSON}" "qiime2_version" "succeeded" "QIIME2 image runs (qiime --version ok)" "docker" "docker run ${QIIME2_IMAGE} qiime --version" "0" "${started}" "${ended}"
fi

# Manifest paths inside mounted /run
QIIME2_MANIFEST_TSV="${QIIME2_DIR}/manifest.tsv"
MANIFEST_R1="/run/sr_amp/inputs/fastq/$(basename "${STAGED_R1}")"
MANIFEST_R2=""
if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  MANIFEST_R2="/run/sr_amp/inputs/fastq/$(basename "${STAGED_R2}")"
fi

# write manifest.tsv
if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  python3 - "${QIIME2_MANIFEST_TSV}" "${SAMPLE_ID}" "${MANIFEST_R1}" "${MANIFEST_R2}" <<'PY'
import sys
out, sample_id, r1, r2 = sys.argv[1:]
with open(out, "w", encoding="utf-8", newline="") as f:
    f.write("sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n")
    f.write(f"{sample_id}\t{r1}\t{r2}\n")
PY
else
  python3 - "${QIIME2_MANIFEST_TSV}" "${SAMPLE_ID}" "${MANIFEST_R1}" <<'PY'
import sys
out, sample_id, r1 = sys.argv[1:]
with open(out, "w", encoding="utf-8", newline="") as f:
    f.write("sample-id\tabsolute-filepath\n")
    f.write(f"{sample_id}\t{r1}\n")
PY
fi

# artifact paths (host)
if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  QIIME2_DEMUX_QZA="${QIIME2_DIR}/demux-paired-end.qza"
  QIIME2_DEMUX_QZV="${QIIME2_DIR}/demux-paired-end.qzv"
else
  QIIME2_DEMUX_QZA="${QIIME2_DIR}/demux-single-end.qza"
  QIIME2_DEMUX_QZV="${QIIME2_DIR}/demux-single-end.qzv"
fi

QIIME2_TRIMMED_QZA="${QIIME2_DIR}/trimmed.qza"
QIIME2_TRIMMED_QZV="${QIIME2_DIR}/trimmed.qzv"
QIIME2_TABLE_QZA="${QIIME2_DIR}/table.qza"
QIIME2_REPSEQ_QZA="${QIIME2_DIR}/rep-seqs.qza"
QIIME2_DADA2_STATS_QZA="${QIIME2_DIR}/denoising-stats.qza"
QIIME2_TABLE_QZV="${QIIME2_DIR}/table.qzv"
QIIME2_REPSEQ_QZV="${QIIME2_DIR}/rep-seqs.qzv"
QIIME2_DADA2_STATS_QZV="${QIIME2_DIR}/denoising-stats.qzv"

QIIME2_TAXONOMY_QZA="${QIIME2_DIR}/taxonomy.qza"
QIIME2_TAXONOMY_QZV="${QIIME2_DIR}/taxonomy.qzv"
QIIME2_TAXA_BARPLOT_QZV="${QIIME2_DIR}/taxa-barplot.qzv"

QIIME2_PHYLOGENY_DIR="${QIIME2_DIR}/phylogeny"
QIIME2_DIVERSITY_DIR="${QIIME2_DIR}/diversity"
QIIME2_ALPHA_DIR="${QIIME2_DIVERSITY_DIR}/alpha"
mkdir -p "${QIIME2_PHYLOGENY_DIR}" "${QIIME2_DIVERSITY_DIR}" "${QIIME2_ALPHA_DIR}"

QIIME2_ROOTED_TREE_QZA="${QIIME2_PHYLOGENY_DIR}/rooted-tree.qza"

QIIME2_ALPHA_SHANNON_QZA="${QIIME2_ALPHA_DIR}/shannon.qza"
QIIME2_ALPHA_OBS_QZA="${QIIME2_ALPHA_DIR}/observed_features.qza"
QIIME2_ALPHA_PIELOU_QZA="${QIIME2_ALPHA_DIR}/pielou_e.qza"

QIIME2_ALPHA_SHANNON_EXPORT_DIR="${QIIME2_ALPHA_DIR}/shannon_export"
QIIME2_ALPHA_OBS_EXPORT_DIR="${QIIME2_ALPHA_DIR}/observed_features_export"
QIIME2_ALPHA_PIELOU_EXPORT_DIR="${QIIME2_ALPHA_DIR}/pielou_e_export"

QIIME2_ALPHA_SHANNON_TSV="${QIIME2_ALPHA_SHANNON_EXPORT_DIR}/alpha-diversity.tsv"
QIIME2_ALPHA_OBS_TSV="${QIIME2_ALPHA_OBS_EXPORT_DIR}/alpha-diversity.tsv"
QIIME2_ALPHA_PIELOU_TSV="${QIIME2_ALPHA_PIELOU_EXPORT_DIR}/alpha-diversity.tsv"

CLASSIFIER_QZA_INNER=""
if [[ -n "${STAGED_CLASSIFIER}" ]]; then
  CLASSIFIER_QZA_INNER="/run/sr_amp/inputs/reference/$(basename "${STAGED_CLASSIFIER}")"
fi

META_TSV_INNER=""
if [[ -n "${STAGED_META_NORMALIZED}" ]]; then
  META_TSV_INNER="/run/sr_amp/inputs/metadata/$(basename "${STAGED_META_NORMALIZED}")"
elif [[ -n "${STAGED_META}" ]]; then
  META_TSV_INNER="/run/sr_amp/inputs/metadata/$(basename "${STAGED_META}")"
fi

# Import
if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  qiime2_run "qiime2_import" qiime tools import \
    --type "SampleData[PairedEndSequencesWithQuality]" \
    --input-path "/run/sr_amp/results/qiime2/manifest.tsv" \
    --output-path "/run/sr_amp/results/qiime2/demux-paired-end.qza" \
    --input-format PairedEndFastqManifestPhred33V2 || exit 3
else
  qiime2_run "qiime2_import" qiime tools import \
    --type "SampleData[SequencesWithQuality]" \
    --input-path "/run/sr_amp/results/qiime2/manifest.tsv" \
    --output-path "/run/sr_amp/results/qiime2/demux-single-end.qza" \
    --input-format SingleEndFastqManifestPhred33V2 || exit 3
fi

# Demux summarize
qiime2_run "qiime2_demux_summarize" qiime demux summarize \
  --i-data "/run/sr_amp/results/qiime2/$(basename "${QIIME2_DEMUX_QZA}")" \
  --o-visualization "/run/sr_amp/results/qiime2/$(basename "${QIIME2_DEMUX_QZV}")" || exit 3

# Primer trimming (optional)
INPUT_FOR_DADA2="/run/sr_amp/results/qiime2/$(basename "${QIIME2_DEMUX_QZA}")"
if [[ -n "${PRIMER_FWD}" || -n "${PRIMER_REV}" ]]; then
  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    if [[ -n "${PRIMER_FWD}" && -n "${PRIMER_REV}" ]]; then
      qiime2_run "qiime2_cutadapt" qiime cutadapt trim-paired \
        --i-demultiplexed-sequences "${INPUT_FOR_DADA2}" \
        --p-front-f "${PRIMER_FWD}" \
        --p-front-r "${PRIMER_REV}" \
        --p-cores 1 \
        --o-trimmed-sequences "/run/sr_amp/results/qiime2/trimmed.qza" || exit 3
      INPUT_FOR_DADA2="/run/sr_amp/results/qiime2/trimmed.qza"
      qiime2_run "qiime2_trimmed_summarize" qiime demux summarize \
        --i-data "/run/sr_amp/results/qiime2/trimmed.qza" \
        --o-visualization "/run/sr_amp/results/qiime2/trimmed.qzv" || exit 3
    else
      started="$(iso_now)"; ended="$(iso_now)"
      steps_append "${STEPS_JSON}" "qiime2_cutadapt" "skipped" "Primer trimming skipped: FASTQ_PAIRED requires both forward and reverse primers" "" "" "0" "${started}" "${ended}"
    fi
  else
    if [[ -n "${PRIMER_FWD}" ]]; then
      qiime2_run "qiime2_cutadapt" qiime cutadapt trim-single \
        --i-demultiplexed-sequences "${INPUT_FOR_DADA2}" \
        --p-front "${PRIMER_FWD}" \
        --p-cores 1 \
        --o-trimmed-sequences "/run/sr_amp/results/qiime2/trimmed.qza" || exit 3
      INPUT_FOR_DADA2="/run/sr_amp/results/qiime2/trimmed.qza"
    elif [[ -n "${PRIMER_REV}" ]]; then
      qiime2_run "qiime2_cutadapt" qiime cutadapt trim-single \
        --i-demultiplexed-sequences "${INPUT_FOR_DADA2}" \
        --p-adapter "${PRIMER_REV}" \
        --p-cores 1 \
        --o-trimmed-sequences "/run/sr_amp/results/qiime2/trimmed.qza" || exit 3
      INPUT_FOR_DADA2="/run/sr_amp/results/qiime2/trimmed.qza"
    else
      started="$(iso_now)"; ended="$(iso_now)"
      steps_append "${STEPS_JSON}" "qiime2_cutadapt" "skipped" "No primers provided; skipping primer trimming" "" "" "0" "${started}" "${ended}"
    fi
  fi
else
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "qiime2_cutadapt" "skipped" "No primers provided; skipping primer trimming" "" "" "0" "${started}" "${ended}"
fi

# DADA2
[[ -n "${DADA2_TRIM_LEFT_F}" ]] || DADA2_TRIM_LEFT_F="0"
[[ -n "${DADA2_TRIM_LEFT_R}" ]] || DADA2_TRIM_LEFT_R="0"
[[ -n "${DADA2_TRUNC_LEN_F}" ]] || DADA2_TRUNC_LEN_F="0"
[[ -n "${DADA2_TRUNC_LEN_R}" ]] || DADA2_TRUNC_LEN_R="0"
[[ -n "${DADA2_N_THREADS}" ]] || DADA2_N_THREADS="0"

if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  if [[ "${DADA2_TRUNC_LEN_F}" -le 0 || "${DADA2_TRUNC_LEN_R}" -le 0 ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "qiime2_dada2" "failed" "DADA2 paired requires trunc_len_f and trunc_len_r > 0" "" "" "2" "${started}" "${ended}"
    echo "ERROR: DADA2 paired requires qiime2.dada2.trunc_len_f and trunc_len_r > 0" >&2
    exit 2
  fi

  qiime2_run "qiime2_dada2" qiime dada2 denoise-paired \
    --i-demultiplexed-seqs "${INPUT_FOR_DADA2}" \
    --p-trim-left-f "${DADA2_TRIM_LEFT_F}" \
    --p-trim-left-r "${DADA2_TRIM_LEFT_R}" \
    --p-trunc-len-f "${DADA2_TRUNC_LEN_F}" \
    --p-trunc-len-r "${DADA2_TRUNC_LEN_R}" \
    --p-n-threads "${DADA2_N_THREADS}" \
    --o-table "/run/sr_amp/results/qiime2/table.qza" \
    --o-representative-sequences "/run/sr_amp/results/qiime2/rep-seqs.qza" \
    --o-denoising-stats "/run/sr_amp/results/qiime2/denoising-stats.qza" || {
      echo "ERROR: DADA2 failed. Check:" >&2
      echo "  - ${QIIME2_LOG}" >&2
      echo "  - ${QIIME2_TMP_DIR} (q2cli debug logs land here via TMPDIR)" >&2
      exit 3
    }
else
  if [[ "${DADA2_TRUNC_LEN_F}" -le 0 ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "qiime2_dada2" "failed" "DADA2 single requires trunc_len_f > 0" "" "" "2" "${started}" "${ended}"
    echo "ERROR: DADA2 single requires qiime2.dada2.trunc_len_f > 0" >&2
    exit 2
  fi

  qiime2_run "qiime2_dada2" qiime dada2 denoise-single \
    --i-demultiplexed-seqs "${INPUT_FOR_DADA2}" \
    --p-trim-left "${DADA2_TRIM_LEFT_F}" \
    --p-trunc-len "${DADA2_TRUNC_LEN_F}" \
    --p-n-threads "${DADA2_N_THREADS}" \
    --o-table "/run/sr_amp/results/qiime2/table.qza" \
    --o-representative-sequences "/run/sr_amp/results/qiime2/rep-seqs.qza" \
    --o-denoising-stats "/run/sr_amp/results/qiime2/denoising-stats.qza" || {
      echo "ERROR: DADA2 failed. Check:" >&2
      echo "  - ${QIIME2_LOG}" >&2
      echo "  - ${QIIME2_TMP_DIR} (q2cli debug logs land here via TMPDIR)" >&2
      exit 3
    }
fi

# Summaries
qiime2_run "qiime2_table_summarize" qiime feature-table summarize \
  --i-table "/run/sr_amp/results/qiime2/table.qza" \
  --o-visualization "/run/sr_amp/results/qiime2/table.qzv" || exit 3

qiime2_run "qiime2_repseqs_tabulate" qiime feature-table tabulate-seqs \
  --i-data "/run/sr_amp/results/qiime2/rep-seqs.qza" \
  --o-visualization "/run/sr_amp/results/qiime2/rep-seqs.qzv" || exit 3

qiime2_run "qiime2_denoising_stats_tabulate" qiime metadata tabulate \
  --m-input-file "/run/sr_amp/results/qiime2/denoising-stats.qza" \
  --o-visualization "/run/sr_amp/results/qiime2/denoising-stats.qzv" || exit 3

# Taxonomy + barplot (optional)
if [[ -n "${CLASSIFIER_QZA_INNER}" ]]; then
  qiime2_run "qiime2_taxonomy" qiime feature-classifier classify-sklearn \
    --i-classifier "${CLASSIFIER_QZA_INNER}" \
    --i-reads "/run/sr_amp/results/qiime2/rep-seqs.qza" \
    --o-classification "/run/sr_amp/results/qiime2/taxonomy.qza" || exit 3

  qiime2_run "qiime2_taxonomy_tabulate" qiime metadata tabulate \
    --m-input-file "/run/sr_amp/results/qiime2/taxonomy.qza" \
    --o-visualization "/run/sr_amp/results/qiime2/taxonomy.qzv" || exit 3

  if [[ -n "${META_TSV_INNER}" ]]; then
    qiime2_run "qiime2_taxa_barplot" qiime taxa barplot \
      --i-table "/run/sr_amp/results/qiime2/table.qza" \
      --i-taxonomy "/run/sr_amp/results/qiime2/taxonomy.qza" \
      --m-metadata-file "${META_TSV_INNER}" \
      --o-visualization "/run/sr_amp/results/qiime2/taxa-barplot.qzv" || exit 3
  else
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "qiime2_taxa_barplot" "skipped" "No metadata TSV provided; skipping taxa barplot" "" "" "0" "${started}" "${ended}"
  fi
else
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "qiime2_taxonomy" "skipped" "No classifier provided; skipping taxonomy" "" "" "0" "${started}" "${ended}"
fi

# Alpha diversity (always)
rm -rf "${QIIME2_ALPHA_SHANNON_EXPORT_DIR}" "${QIIME2_ALPHA_OBS_EXPORT_DIR}" "${QIIME2_ALPHA_PIELOU_EXPORT_DIR}"

qiime2_run "qiime2_diversity_alpha_shannon" qiime diversity alpha \
  --i-table "/run/sr_amp/results/qiime2/table.qza" \
  --p-metric shannon \
  --o-alpha-diversity "/run/sr_amp/results/qiime2/diversity/alpha/shannon.qza" || exit 3

qiime2_run "qiime2_diversity_alpha_observed" qiime diversity alpha \
  --i-table "/run/sr_amp/results/qiime2/table.qza" \
  --p-metric observed_features \
  --o-alpha-diversity "/run/sr_amp/results/qiime2/diversity/alpha/observed_features.qza" || exit 3

qiime2_run "qiime2_diversity_alpha_pielou" qiime diversity alpha \
  --i-table "/run/sr_amp/results/qiime2/table.qza" \
  --p-metric pielou_e \
  --o-alpha-diversity "/run/sr_amp/results/qiime2/diversity/alpha/pielou_e.qza" || exit 3

qiime2_run "qiime2_diversity_alpha_export_shannon" qiime tools export \
  --input-path "/run/sr_amp/results/qiime2/diversity/alpha/shannon.qza" \
  --output-path "/run/sr_amp/results/qiime2/diversity/alpha/shannon_export" || exit 3

qiime2_run "qiime2_diversity_alpha_export_observed" qiime tools export \
  --input-path "/run/sr_amp/results/qiime2/diversity/alpha/observed_features.qza" \
  --output-path "/run/sr_amp/results/qiime2/diversity/alpha/observed_features_export" || exit 3

qiime2_run "qiime2_diversity_alpha_export_pielou" qiime tools export \
  --input-path "/run/sr_amp/results/qiime2/diversity/alpha/pielou_e.qza" \
  --output-path "/run/sr_amp/results/qiime2/diversity/alpha/pielou_e_export" || exit 3

steps_append "${STEPS_JSON}" "qiime2_diversity_alpha" "succeeded" "Alpha diversity exported (shannon, observed_features, pielou_e)" "docker" "qiime diversity alpha + export" "0" "$(iso_now)" "$(iso_now)"

# Core metrics (optional)
if [[ -n "${SAMPLING_DEPTH}" && "${SAMPLING_DEPTH}" -gt 0 ]]; then
  if [[ -z "${META_TSV_INNER}" ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "qiime2_diversity_core" "failed" "Core metrics requested but no metadata TSV provided (qiime2.diversity.metadata_tsv)" "" "" "2" "${started}" "${ended}"
    echo "ERROR: Core metrics requested but metadata TSV is missing." >&2
    exit 2
  fi

  qiime2_run "qiime2_phylogeny" qiime phylogeny align-to-tree-mafft-fasttree \
    --i-sequences "/run/sr_amp/results/qiime2/rep-seqs.qza" \
    --o-alignment "/run/sr_amp/results/qiime2/phylogeny/aligned-rep-seqs.qza" \
    --o-masked-alignment "/run/sr_amp/results/qiime2/phylogeny/masked-aligned-rep-seqs.qza" \
    --o-tree "/run/sr_amp/results/qiime2/phylogeny/unrooted-tree.qza" \
    --o-rooted-tree "/run/sr_amp/results/qiime2/phylogeny/rooted-tree.qza" || exit 3

  qiime2_run "qiime2_diversity_core" qiime diversity core-metrics-phylogenetic \
    --i-phylogeny "/run/sr_amp/results/qiime2/phylogeny/rooted-tree.qza" \
    --i-table "/run/sr_amp/results/qiime2/table.qza" \
    --p-sampling-depth "${SAMPLING_DEPTH}" \
    --m-metadata-file "${META_TSV_INNER}" \
    --output-dir "/run/sr_amp/results/qiime2/diversity/core-metrics-results" || exit 3
else
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "qiime2_diversity_core" "skipped" "Core metrics skipped: sampling_depth not set (>0 required)" "" "" "0" "${started}" "${ended}"
fi

# Exports
QIIME2_EXPORT_DIR="${QIIME2_DIR}/exports"
QIIME2_EXPORT_TABLE_DIR="${QIIME2_EXPORT_DIR}/table"
QIIME2_EXPORT_REPSEQS_DIR="${QIIME2_EXPORT_DIR}/rep-seqs"
QIIME2_EXPORT_TAXONOMY_DIR="${QIIME2_EXPORT_DIR}/taxonomy"
QIIME2_EXPORT_PHYLOGENY_DIR="${QIIME2_EXPORT_DIR}/phylogeny"
mkdir -p "${QIIME2_EXPORT_TABLE_DIR}" "${QIIME2_EXPORT_REPSEQS_DIR}" "${QIIME2_EXPORT_TAXONOMY_DIR}" "${QIIME2_EXPORT_PHYLOGENY_DIR}"

qiime2_run "qiime2_export_table" qiime tools export \
  --input-path "/run/sr_amp/results/qiime2/table.qza" \
  --output-path "/run/sr_amp/results/qiime2/exports/table" || exit 3

# biom convert (best-effort)
set +e
{
  echo
  echo "[biom] attempting biom convert"
} >>"${QIIME2_LOG}"
"${qiime2_docker_base[@]}" biom convert \
  -i "/run/sr_amp/results/qiime2/exports/table/feature-table.biom" \
  -o "/run/sr_amp/results/qiime2/exports/table/feature-table.tsv" \
  --to-tsv >>"${QIIME2_LOG}" 2>&1
set -e

qiime2_run "qiime2_export_repseqs" qiime tools export \
  --input-path "/run/sr_amp/results/qiime2/rep-seqs.qza" \
  --output-path "/run/sr_amp/results/qiime2/exports/rep-seqs" || exit 3

if [[ -f "${QIIME2_TAXONOMY_QZA}" ]]; then
  qiime2_run "qiime2_export_taxonomy" qiime tools export \
    --input-path "/run/sr_amp/results/qiime2/taxonomy.qza" \
    --output-path "/run/sr_amp/results/qiime2/exports/taxonomy" || exit 3
fi

if [[ -f "${QIIME2_ROOTED_TREE_QZA}" ]]; then
  qiime2_run "qiime2_export_phylogeny" qiime tools export \
    --input-path "/run/sr_amp/results/qiime2/phylogeny/rooted-tree.qza" \
    --output-path "/run/sr_amp/results/qiime2/exports/phylogeny" || exit 3
fi

steps_append "${STEPS_JSON}" "qiime2_exports" "succeeded" "Exported QIIME2 artifacts to results/qiime2/exports; q2cli debug logs go to results/qiime2/tmp via TMPDIR" "docker" "qiime tools export" "0" "$(iso_now)" "$(iso_now)"

# Append key outputs to outputs.json
QIIME2_EXPORT_TABLE_BIOM="${QIIME2_EXPORT_TABLE_DIR}/feature-table.biom"
QIIME2_EXPORT_TABLE_TSV="${QIIME2_EXPORT_TABLE_DIR}/feature-table.tsv"
QIIME2_EXPORT_REPSEQS_FASTA="${QIIME2_EXPORT_REPSEQS_DIR}/dna-sequences.fasta"
QIIME2_EXPORT_TAXONOMY_TSV="${QIIME2_EXPORT_TAXONOMY_DIR}/taxonomy.tsv"
QIIME2_EXPORT_ROOTED_NWK="${QIIME2_EXPORT_PHYLOGENY_DIR}/tree.nwk"

tmp="${OUTPUTS_JSON}.tmp"
jq \
  --arg qiime2_dir "${QIIME2_DIR}" \
  --arg qiime2_log "${QIIME2_LOG}" \
  --arg qiime2_tmp_dir "${QIIME2_TMP_DIR}" \
  --arg qiime2_manifest_tsv "${QIIME2_MANIFEST_TSV}" \
  --arg qiime2_demux_qza "${QIIME2_DEMUX_QZA}" \
  --arg qiime2_demux_qzv "${QIIME2_DEMUX_QZV}" \
  --arg qiime2_trimmed_qza "${QIIME2_TRIMMED_QZA}" \
  --arg qiime2_trimmed_qzv "${QIIME2_TRIMMED_QZV}" \
  --arg qiime2_table_qza "${QIIME2_TABLE_QZA}" \
  --arg qiime2_repseq_qza "${QIIME2_REPSEQ_QZA}" \
  --arg qiime2_dada2_stats_qza "${QIIME2_DADA2_STATS_QZA}" \
  --arg qiime2_table_qzv "${QIIME2_TABLE_QZV}" \
  --arg qiime2_repseq_qzv "${QIIME2_REPSEQ_QZV}" \
  --arg qiime2_dada2_stats_qzv "${QIIME2_DADA2_STATS_QZV}" \
  --arg qiime2_taxonomy_qza "${QIIME2_TAXONOMY_QZA}" \
  --arg qiime2_taxonomy_qzv "${QIIME2_TAXONOMY_QZV}" \
  --arg qiime2_taxa_barplot_qzv "${QIIME2_TAXA_BARPLOT_QZV}" \
  --arg qiime2_rooted_tree_qza "${QIIME2_ROOTED_TREE_QZA}" \
  --arg qiime2_diversity_core_dir "${QIIME2_DIVERSITY_DIR}/core-metrics-results" \
  --arg qiime2_alpha_dir "${QIIME2_ALPHA_DIR}" \
  --arg qiime2_alpha_shannon_tsv "${QIIME2_ALPHA_SHANNON_TSV}" \
  --arg qiime2_alpha_observed_features_tsv "${QIIME2_ALPHA_OBS_TSV}" \
  --arg qiime2_alpha_pielou_e_tsv "${QIIME2_ALPHA_PIELOU_TSV}" \
  --arg qiime2_export_table_biom "${QIIME2_EXPORT_TABLE_BIOM}" \
  --arg qiime2_export_table_tsv "${QIIME2_EXPORT_TABLE_TSV}" \
  --arg qiime2_export_repseqs_fasta "${QIIME2_EXPORT_REPSEQS_FASTA}" \
  --arg qiime2_export_taxonomy_tsv "${QIIME2_EXPORT_TAXONOMY_TSV}" \
  --arg qiime2_export_rooted_nwk "${QIIME2_EXPORT_ROOTED_NWK}" \
  '. + {
    qiime2_dir: $qiime2_dir,
    qiime2_log: $qiime2_log,
    qiime2_tmp_dir: $qiime2_tmp_dir,
    qiime2_artifacts: {
      manifest_tsv: $qiime2_manifest_tsv,
      demux_qza: $qiime2_demux_qza,
      demux_qzv: $qiime2_demux_qzv,
      trimmed_qza: ($qiime2_trimmed_qza | select(length>0) // null),
      trimmed_qzv: ($qiime2_trimmed_qzv | select(length>0) // null),
      table_qza: $qiime2_table_qza,
      rep_seqs_qza: $qiime2_repseq_qza,
      denoising_stats_qza: $qiime2_dada2_stats_qza,
      table_qzv: $qiime2_table_qzv,
      rep_seqs_qzv: $qiime2_repseq_qzv,
      denoising_stats_qzv: $qiime2_dada2_stats_qzv,
      taxonomy_qza: ($qiime2_taxonomy_qza | select(length>0) // null),
      taxonomy_qzv: ($qiime2_taxonomy_qzv | select(length>0) // null),
      taxa_barplot_qzv: ($qiime2_taxa_barplot_qzv | select(length>0) // null),
      rooted_tree_qza: ($qiime2_rooted_tree_qza | select(length>0) // null),
      alpha_diversity_dir: ($qiime2_alpha_dir | select(length>0) // null),
      alpha_diversity_tsv: {
        shannon: ($qiime2_alpha_shannon_tsv | select(length>0) // null),
        observed_features: ($qiime2_alpha_observed_features_tsv | select(length>0) // null),
        pielou_e: ($qiime2_alpha_pielou_e_tsv | select(length>0) // null)
      },
      diversity_core_metrics_dir: ($qiime2_diversity_core_dir | select(length>0) // null),
      exports: {
        feature_table_biom: ($qiime2_export_table_biom | select(length>0) // null),
        feature_table_tsv:  ($qiime2_export_table_tsv  | select(length>0) // null),
        rep_seqs_fasta:     ($qiime2_export_repseqs_fasta | select(length>0) // null),
        taxonomy_tsv:       ($qiime2_export_taxonomy_tsv | select(length>0) // null),
        rooted_tree_nwk:    ($qiime2_export_rooted_nwk | select(length>0) // null)
      }
    }
  }' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

echo "[${MODULE_NAME}] Done"
print_step_status "${STEPS_JSON}" "fastqc"
print_step_status "${STEPS_JSON}" "multiqc"
print_step_status "${STEPS_JSON}" "metadata_normalize"
print_step_status "${STEPS_JSON}" "qiime2_version"
print_step_status "${STEPS_JSON}" "qiime2_import"
print_step_status "${STEPS_JSON}" "qiime2_demux_summarize"
print_step_status "${STEPS_JSON}" "qiime2_cutadapt"
print_step_status "${STEPS_JSON}" "qiime2_dada2"
print_step_status "${STEPS_JSON}" "qiime2_taxonomy"
print_step_status "${STEPS_JSON}" "qiime2_diversity_alpha"
print_step_status "${STEPS_JSON}" "qiime2_diversity_core"
print_step_status "${STEPS_JSON}" "qiime2_exports"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
