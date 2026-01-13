#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="lr_amp"

usage() { echo "Usage: $0 --config <config.json>"; }

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
    if [[ -n "${v}" && "${v}" != "null" ]]; then echo "${v}"; return 0; fi
  done
  return 1
}

require_file() { local p="$1"; [[ -n "${p}" && "${p}" != "null" ]] || { echo "ERROR: Required file path is empty" >&2; exit 2; }; [[ -f "${p}" ]] || { echo "ERROR: File not found: ${p}" >&2; exit 2; }; }
require_dir() { local p="$1"; [[ -n "${p}" && "${p}" != "null" ]] || { echo "ERROR: Required directory path is empty" >&2; exit 2; }; [[ -d "${p}" ]] || { echo "ERROR: Directory not found: ${p}" >&2; exit 2; }; }

resolve_fastq_single() {
  local p="$1"
  [[ -n "${p}" && "${p}" != "null" ]] || { echo ""; return 0; }
  if [[ -f "${p}" ]]; then echo "${p}"; return 0; fi
  if [[ -d "${p}" ]]; then
    local found=""
    found="$(find "${p}" -maxdepth 1 -type f \( -iname "*.fastq" -o -iname "*.fq" -o -iname "*.fastq.gz" -o -iname "*.fq.gz" \) | sort | head -n 1 || true)"
    [[ -n "${found}" ]] && { echo "${found}"; return 0; }
  fi
  echo ""
}

count_fastq_lines() {
  local p="$1"
  require_file "${p}"
  if [[ "${p}" == *.gz ]]; then gzip -cd "${p}" | wc -l | tr -d ' '; else wc -l < "${p}" | tr -d ' '; fi
}

estimate_reads_from_lines() {
  local lines="$1"
  python3 - "$lines" <<'PY'
import sys
lines = int(sys.argv[1])
print(lines // 4)
PY
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
status = x.get("status","")
msg = x.get("message","")
print(f"[{module}] {step}: {status} - {msg}")
PY
}

INPUT_STYLE="$(jq_first "${CONFIG_PATH}" '.input.style' '.inputs.style' '.input_style' '.inputs.input_style' || true)"
[[ -n "${INPUT_STYLE}" ]] || INPUT_STYLE="FASTQ_SINGLE"

OUTPUT_DIR="$(jq_first "${CONFIG_PATH}" '.run.work_dir' '.output_dir' '.run.output_dir' '.outputs.output_dir' '.output.output_dir' || true)"
[[ -n "${OUTPUT_DIR}" ]] || { echo "ERROR: Could not determine output dir from config" >&2; exit 2; }
mkdir -p "${OUTPUT_DIR}"

RUN_ID="$(jq_first "${CONFIG_PATH}" '.run.run_id' '.run_id' '.id' '.run.id' || true)"
PIPELINE_ID="$(jq_first "${CONFIG_PATH}" '.pipeline_id' '.run.pipeline_id' '.pipeline.id' || true)"
if [[ -n "${PIPELINE_ID:-}" && "${PIPELINE_ID}" != "${MODULE_NAME}" ]]; then
  echo "ERROR: Config pipeline_id (${PIPELINE_ID}) does not match module (${MODULE_NAME})." >&2
  exit 2
fi

MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
FASTQ_STAGE_DIR="${MODULE_OUT_DIR}/inputs/fastq"
FAST5_STAGE_DIR="${MODULE_OUT_DIR}/inputs/fast5"
RESULTS_DIR="${MODULE_OUT_DIR}/results"
LOGS_DIR="${MODULE_OUT_DIR}/logs"
STEPS_JSON="${MODULE_OUT_DIR}/steps.json"
mkdir -p "${FASTQ_STAGE_DIR}" "${FAST5_STAGE_DIR}" "${RESULTS_DIR}" "${LOGS_DIR}"

STAGED_FASTQ=""
STAGED_FAST5_DIR=""

case "${INPUT_STYLE}" in
  FASTQ_SINGLE)
    FASTQ_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq' '.inputs.fastq' '.input.fastq_r1' '.inputs.fastq_single' '.inputs.fastq_path' '.fastq' '.fastq_single' || true)"
    FASTQ_RESOLVED="$(resolve_fastq_single "${FASTQ_SRC}")"
    [[ -n "${FASTQ_RESOLVED}" ]] || { echo "ERROR: FASTQ_SINGLE selected but could not resolve a FASTQ file from config." >&2; exit 2; }
    require_file "${FASTQ_RESOLVED}"
    STAGED_FASTQ="${FASTQ_STAGE_DIR}/$(basename "${FASTQ_RESOLVED}")"
    ln -sfn "${FASTQ_RESOLVED}" "${STAGED_FASTQ}"
    ;;
  FAST5_DIR|FAST5)
    FAST5_DIR_SRC="$(jq_first "${CONFIG_PATH}" '.input.fast5_dir' '.inputs.fast5_dir' '.input.fast5' '.inputs.fast5' '.fast5_dir' '.fast5' || true)"
    [[ -n "${FAST5_DIR_SRC}" ]] || { echo "ERROR: FAST5 selected but no fast5_dir found in config" >&2; exit 2; }
    require_dir "${FAST5_DIR_SRC}"
    STAGED_FAST5_DIR="${FAST5_STAGE_DIR}/fast5"
    ln -sfn "${FAST5_DIR_SRC}" "${STAGED_FAST5_DIR}"
    ;;
  *)
    echo "ERROR: Unsupported input style: ${INPUT_STYLE}" >&2
    exit 2
    ;;
esac

OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"
jq -n \
  --arg module_name "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg fastq "${STAGED_FASTQ}" \
  --arg fast5_dir "${STAGED_FAST5_DIR}" \
  '{
    "module": $module_name,
    "pipeline_id": $pipeline_id,
    "run_id": $run_id,
    "input_style": $input_style,
    "inputs": (
      if $input_style == "FASTQ_SINGLE" then
        { "fastq": $fastq }
      elif ($input_style == "FAST5_DIR" or $input_style == "FAST5") then
        { "fast5_dir": $fast5_dir }
      else
        {}
      end
    )
  }' > "${OUTPUTS_JSON}"

METRICS_JSON="${MODULE_OUT_DIR}/metrics.json"
if [[ "${INPUT_STYLE}" == "FASTQ_SINGLE" ]]; then
  STAGED_PATH="$(jq -r '.inputs.fastq // empty' "${OUTPUTS_JSON}")"
  [[ -n "${STAGED_PATH}" ]] || { echo "ERROR: outputs.json missing .inputs.fastq" >&2; exit 2; }
  LINES="$(count_fastq_lines "${STAGED_PATH}")"
  READS="$(estimate_reads_from_lines "${LINES}")"
  jq -n --arg module_name "${MODULE_NAME}" --arg fastq "${STAGED_PATH}" \
    --argjson fastq_lines "${LINES}" --argjson reads_estimate "${READS}" \
    '{ "module": $module_name, "fastq": $fastq, "fastq_lines": $fastq_lines, "reads_estimate": $reads_estimate }' > "${METRICS_JSON}"
else
  jq -n --arg module_name "${MODULE_NAME}" --arg note "metrics skipped (input_style is not FASTQ_SINGLE)" \
    '{ "module": $module_name, "note": $note }' > "${METRICS_JSON}"
fi

tmp="${OUTPUTS_JSON}.tmp"
jq --arg metrics_path "${METRICS_JSON}" --slurpfile metrics "${METRICS_JSON}" \
  '. + {"metrics_path":$metrics_path, "metrics":$metrics[0]}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

FASTQC_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.fastqc_bin' 'fastqc')"
FASTQC_LOG="${LOGS_DIR}/fastqc.log"
FASTQC_OUTDIR="${RESULTS_DIR}/fastqc"

if [[ "${INPUT_STYLE}" != "FASTQ_SINGLE" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "fastqc" "skipped" "fastqc only runs for FASTQ_SINGLE in this module" "${FASTQC_BIN}" "" "0" "${started}" "${ended}"
else
  STAGED_PATH="$(jq -r '.inputs.fastq // empty' "${OUTPUTS_JSON}")"
  [[ -n "${STAGED_PATH}" ]] || { echo "ERROR: outputs.json missing .inputs.fastq for fastqc" >&2; exit 2; }

  if [[ -z "${FASTQC_BIN}" ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "fastqc" "skipped" "fastqc not found (install fastqc or set tools.fastqc_bin)" "" "" "0" "${started}" "${ended}"
  else
    mkdir -p "${FASTQC_OUTDIR}"
    started="$(iso_now)"
    set +e
    "${FASTQC_BIN}" -o "${FASTQC_OUTDIR}" "${STAGED_PATH}" >"${FASTQC_LOG}" 2>&1
    ec=$?
    set -e
    ended="$(iso_now)"

    if exit_code_means_tool_missing "${ec}"; then
      steps_append "${STEPS_JSON}" "fastqc" "skipped" "fastqc command not found at runtime (check tools.fastqc_bin / PATH)" "${FASTQC_BIN}" "${FASTQC_BIN} -o ${FASTQC_OUTDIR} ${STAGED_PATH}" "${ec}" "${started}" "${ended}"
    elif [[ $ec -eq 0 ]]; then
      steps_append "${STEPS_JSON}" "fastqc" "succeeded" "fastqc completed" "${FASTQC_BIN}" "${FASTQC_BIN} -o ${FASTQC_OUTDIR} ${STAGED_PATH}" "${ec}" "${started}" "${ended}"
    else
      steps_append "${STEPS_JSON}" "fastqc" "failed" "fastqc failed (see logs/fastqc.log)" "${FASTQC_BIN}" "${FASTQC_BIN} -o ${FASTQC_OUTDIR} ${STAGED_PATH}" "${ec}" "${started}" "${ended}"
    fi
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
    steps_append "${STEPS_JSON}" "multiqc" "skipped" "multiqc command not found at runtime (check tools.multiqc_bin / PATH)" "${MULTIQC_BIN}" "${MULTIQC_BIN} -o ${MULTIQC_OUTDIR} ${RESULTS_DIR}" "${ec}" "${started}" "${ended}"
  elif [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "multiqc" "succeeded" "multiqc completed" "${MULTIQC_BIN}" "${MULTIQC_BIN} -o ${MULTIQC_OUTDIR} ${RESULTS_DIR}" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "multiqc" "failed" "multiqc failed (see logs/multiqc.log)" "${MULTIQC_BIN}" "${MULTIQC_BIN} -o ${MULTIQC_OUTDIR} ${RESULTS_DIR}" "${ec}" "${started}" "${ended}"
  fi
fi

MULTIQC_REPORT="${MULTIQC_OUTDIR}/multiqc_report.html"
tmp="${OUTPUTS_JSON}.tmp"
jq --arg steps_path "${STEPS_JSON}" \
   --arg multiqc_dir "${MULTIQC_OUTDIR}" \
   --arg multiqc_report_html "${MULTIQC_REPORT}" \
   '. + {"steps_path":$steps_path, "multiqc_dir":$multiqc_dir, "multiqc_report_html":$multiqc_report_html}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

echo "[${MODULE_NAME}] Step 7B staging complete"
echo "[${MODULE_NAME}] Step 7C metrics complete"
print_step_status "${STEPS_JSON}" "fastqc"
print_step_status "${STEPS_JSON}" "multiqc"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
