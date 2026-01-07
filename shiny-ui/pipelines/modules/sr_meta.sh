#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="sr_meta"

usage() {
  echo "Usage: $0 --config <config.json>"
}

CONFIG_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${CONFIG_PATH}" ]]; then
  echo "ERROR: --config is required" >&2
  usage
  exit 2
fi
if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "ERROR: Config not found: ${CONFIG_PATH}" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 2
fi

jq_first() {
  local file="$1"
  shift
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

require_file() {
  local p="$1"
  if [[ -z "${p}" || "${p}" == "null" ]]; then
    echo "ERROR: Required file path is empty" >&2
    exit 2
  fi
  if [[ ! -f "${p}" ]]; then
    echo "ERROR: File not found: ${p}" >&2
    exit 2
  fi
}

count_fastq_lines() {
  local p="$1"
  require_file "${p}"
  if [[ "${p}" == *.gz ]]; then
    gzip -cd "${p}" | wc -l | tr -d ' '
  else
    wc -l < "${p}" | tr -d ' '
  fi
}

estimate_reads_from_lines() {
  local lines="$1"
  python3 - "$lines" <<'PY'
import sys
lines = int(sys.argv[1])
print(lines // 4)
PY
}

INPUT_STYLE="$(jq_first "${CONFIG_PATH}" '.input.style' '.inputs.style' '.input_style' '.inputs.input_style' || true)"
if [[ -z "${INPUT_STYLE}" ]]; then
  INPUT_STYLE="FASTQ_PAIRED"
fi
if [[ "${INPUT_STYLE}" != "FASTQ_PAIRED" ]]; then
  echo "ERROR: ${MODULE_NAME} expects FASTQ_PAIRED, got: ${INPUT_STYLE}" >&2
  exit 2
fi

OUTPUT_DIR="$(jq_first "${CONFIG_PATH}" '.run.work_dir' '.output_dir' '.run.output_dir' '.outputs.output_dir' '.output.output_dir' || true)"
if [[ -z "${OUTPUT_DIR}" ]]; then
  echo "ERROR: Could not determine output dir from config. Expected one of: .run.work_dir, .output_dir, .run.output_dir" >&2
  exit 2
fi
mkdir -p "${OUTPUT_DIR}"

RUN_ID="$(jq_first "${CONFIG_PATH}" '.run.run_id' '.run_id' '.id' '.run.id' || true)"
PIPELINE_ID="$(jq_first "${CONFIG_PATH}" '.pipeline_id' '.run.pipeline_id' '.pipeline.id' || true)"

if [[ -n "${PIPELINE_ID:-}" && "${PIPELINE_ID}" != "${MODULE_NAME}" ]]; then
  echo "ERROR: Config pipeline_id (${PIPELINE_ID}) does not match module (${MODULE_NAME})." >&2
  echo "       Use the matching config for this module." >&2
  exit 2
fi

FASTQ_R1_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq_r1' '.inputs.fastq_r1' '.input.r1' '.inputs.r1' '.input.read1' '.inputs.read1' || true)"
FASTQ_R2_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq_r2' '.inputs.fastq_r2' '.input.r2' '.inputs.r2' '.input.read2' '.inputs.read2' || true)"

if [[ -z "${FASTQ_R1_SRC}" || -z "${FASTQ_R2_SRC}" ]]; then
  echo "ERROR: FASTQ_PAIRED requires both fastq_r1 and fastq_r2 in config." >&2
  echo "Tried: .input.fastq_r1/.input.fastq_r2 (and .inputs.* variants)" >&2
  exit 2
fi

require_file "${FASTQ_R1_SRC}"
require_file "${FASTQ_R2_SRC}"

MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
FASTQ_STAGE_DIR="${MODULE_OUT_DIR}/inputs/fastq"
mkdir -p "${FASTQ_STAGE_DIR}" "${MODULE_OUT_DIR}"

R1_BASENAME="$(basename "${FASTQ_R1_SRC}")"
R2_BASENAME="$(basename "${FASTQ_R2_SRC}")"

STAGED_R1="${FASTQ_STAGE_DIR}/${R1_BASENAME}"
STAGED_R2="${FASTQ_STAGE_DIR}/${R2_BASENAME}"

# ---- Step 7B: Stage inputs ----
ln -sfn "${FASTQ_R1_SRC}" "${STAGED_R1}"
ln -sfn "${FASTQ_R2_SRC}" "${STAGED_R2}"

OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"
jq -n \
  --arg module "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg fastq_r1 "${STAGED_R1}" \
  --arg fastq_r2 "${STAGED_R2}" \
  '
  {
    module: $module,
    pipeline_id: $pipeline_id,
    run_id: $run_id,
    input_style: $input_style,
    inputs: {
      fastq_r1: $fastq_r1,
      fastq_r2: $fastq_r2
    }
  }
  ' > "${OUTPUTS_JSON}"

# ---- Step 7C: Metrics from staged inputs ----
METRICS_JSON="${MODULE_OUT_DIR}/metrics.json"

STAGED_R1_PATH="$(jq -r '.inputs.fastq_r1 // empty' "${OUTPUTS_JSON}")"
STAGED_R2_PATH="$(jq -r '.inputs.fastq_r2 // empty' "${OUTPUTS_JSON}")"
if [[ -z "${STAGED_R1_PATH}" || -z "${STAGED_R2_PATH}" ]]; then
  echo "ERROR: outputs.json missing staged paired FASTQ paths" >&2
  exit 2
fi

R1_LINES="$(count_fastq_lines "${STAGED_R1_PATH}")"
R2_LINES="$(count_fastq_lines "${STAGED_R2_PATH}")"
R1_READS="$(estimate_reads_from_lines "${R1_LINES}")"
R2_READS="$(estimate_reads_from_lines "${R2_LINES}")"

jq -n \
  --arg module "${MODULE_NAME}" \
  --arg fastq_r1 "${STAGED_R1_PATH}" \
  --arg fastq_r2 "${STAGED_R2_PATH}" \
  --argjson r1_lines "${R1_LINES}" \
  --argjson r2_lines "${R2_LINES}" \
  --argjson r1_reads_estimate "${R1_READS}" \
  --argjson r2_reads_estimate "${R2_READS}" \
  '{
    module: $module,
    fastq_r1: $fastq_r1,
    fastq_r2: $fastq_r2,
    r1_lines: $r1_lines,
    r2_lines: $r2_lines,
    r1_reads_estimate: $r1_reads_estimate,
    r2_reads_estimate: $r2_reads_estimate
  }' > "${METRICS_JSON}"

tmp="${OUTPUTS_JSON}.tmp"
jq \
  --arg metrics_path "${METRICS_JSON}" \
  --slurpfile metrics "${METRICS_JSON}" \
  '. + { metrics_path: $metrics_path, metrics: $metrics[0] }' \
  "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

echo "[${MODULE_NAME}] Step 7B staging complete"
echo "[${MODULE_NAME}] Step 7C metrics complete"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
