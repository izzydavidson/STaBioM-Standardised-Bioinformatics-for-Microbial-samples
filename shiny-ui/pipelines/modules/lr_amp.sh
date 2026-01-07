#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="lr_amp"

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

require_dir() {
  local p="$1"
  if [[ -z "${p}" || "${p}" == "null" ]]; then
    echo "ERROR: Required directory path is empty" >&2
    exit 2
  fi
  if [[ ! -d "${p}" ]]; then
    echo "ERROR: Directory not found: ${p}" >&2
    exit 2
  fi
}

resolve_fastq_single() {
  local p="$1"
  if [[ -z "${p}" || "${p}" == "null" ]]; then
    echo ""
    return 0
  fi

  if [[ -f "${p}" ]]; then
    echo "${p}"
    return 0
  fi

  if [[ -d "${p}" ]]; then
    local found=""
    found="$(find "${p}" -maxdepth 1 -type f \( -iname "*.fastq" -o -iname "*.fq" -o -iname "*.fastq.gz" -o -iname "*.fq.gz" \) | sort | head -n 1 || true)"
    if [[ -n "${found}" ]]; then
      echo "${found}"
      return 0
    fi
  fi

  echo ""
  return 0
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
  INPUT_STYLE="FASTQ_SINGLE"
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

MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
INPUTS_DIR="${MODULE_OUT_DIR}/inputs"
FASTQ_STAGE_DIR="${INPUTS_DIR}/fastq"
FAST5_STAGE_DIR="${INPUTS_DIR}/fast5"
mkdir -p "${FASTQ_STAGE_DIR}" "${FAST5_STAGE_DIR}" "${MODULE_OUT_DIR}"

STAGED_FASTQ=""
STAGED_FAST5_DIR=""

# ---- Step 7B: Stage inputs ----
case "${INPUT_STYLE}" in
  FASTQ_SINGLE)
    FASTQ_SRC="$(jq_first "${CONFIG_PATH}" '.input.fastq' '.inputs.fastq' '.input.fastq_r1' '.inputs.fastq_single' '.inputs.fastq_path' '.fastq' '.fastq_single' || true)"
    FASTQ_RESOLVED="$(resolve_fastq_single "${FASTQ_SRC}")"
    if [[ -z "${FASTQ_RESOLVED}" ]]; then
      echo "ERROR: FASTQ_SINGLE selected but could not resolve a FASTQ file from config." >&2
      echo "Tried: .input.fastq, .input.fastq_r1, .inputs.fastq, .inputs.fastq_single, etc." >&2
      exit 2
    fi
    require_file "${FASTQ_RESOLVED}"

    FASTQ_BASENAME="$(basename "${FASTQ_RESOLVED}")"
    STAGED_FASTQ="${FASTQ_STAGE_DIR}/${FASTQ_BASENAME}"
    ln -sfn "${FASTQ_RESOLVED}" "${STAGED_FASTQ}"
    ;;
  FAST5_DIR|FAST5)
    FAST5_DIR_SRC="$(jq_first "${CONFIG_PATH}" '.input.fast5_dir' '.inputs.fast5_dir' '.input.fast5' '.inputs.fast5' '.fast5_dir' '.fast5' || true)"
    if [[ -z "${FAST5_DIR_SRC}" ]]; then
      echo "ERROR: FAST5 selected but no fast5_dir/fast5 found in config" >&2
      exit 2
    fi
    require_dir "${FAST5_DIR_SRC}"

    STAGED_FAST5_DIR="${FAST5_STAGE_DIR}/fast5"
    ln -sfn "${FAST5_DIR_SRC}" "${STAGED_FAST5_DIR}"
    ;;
  *)
    echo "ERROR: Unsupported input style: ${INPUT_STYLE}" >&2
    echo "Supported: FASTQ_SINGLE, FAST5_DIR/FAST5" >&2
    exit 2
    ;;
esac

OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"
jq -n \
  --arg module "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg fastq "${STAGED_FASTQ}" \
  --arg fast5_dir "${STAGED_FAST5_DIR}" \
  '
  {
    module: $module,
    pipeline_id: $pipeline_id,
    run_id: $run_id,
    input_style: $input_style,
    inputs: (
      if $input_style == "FASTQ_SINGLE" then
        { fastq: $fastq }
      elif ($input_style == "FAST5_DIR" or $input_style == "FAST5") then
        { fast5_dir: $fast5_dir }
      else
        {}
      end
    )
  }
  ' > "${OUTPUTS_JSON}"

# ---- Step 7C: Metrics from staged inputs (FASTQ only) ----
METRICS_JSON="${MODULE_OUT_DIR}/metrics.json"
if [[ "${INPUT_STYLE}" == "FASTQ_SINGLE" ]]; then
  STAGED_PATH="$(jq -r '.inputs.fastq // empty' "${OUTPUTS_JSON}")"
  if [[ -z "${STAGED_PATH}" ]]; then
    echo "ERROR: outputs.json missing .inputs.fastq after staging" >&2
    exit 2
  fi

  LINES="$(count_fastq_lines "${STAGED_PATH}")"
  READS="$(estimate_reads_from_lines "${LINES}")"

  jq -n \
    --arg module "${MODULE_NAME}" \
    --arg fastq "${STAGED_PATH}" \
    --argjson fastq_lines "${LINES}" \
    --argjson reads_estimate "${READS}" \
    '{
      module: $module,
      fastq: $fastq,
      fastq_lines: $fastq_lines,
      reads_estimate: $reads_estimate
    }' > "${METRICS_JSON}"

  tmp="${OUTPUTS_JSON}.tmp"
  jq \
    --arg metrics_path "${METRICS_JSON}" \
    --slurpfile metrics "${METRICS_JSON}" \
    '. + { metrics_path: $metrics_path, metrics: $metrics[0] }' \
    "${OUTPUTS_JSON}" > "${tmp}"
  mv "${tmp}" "${OUTPUTS_JSON}"
else
  jq -n \
    --arg module "${MODULE_NAME}" \
    --arg note "metrics skipped (input_style is not FASTQ_SINGLE)" \
    '{ module: $module, note: $note }' > "${METRICS_JSON}"

  tmp="${OUTPUTS_JSON}.tmp"
  jq \
    --arg metrics_path "${METRICS_JSON}" \
    --slurpfile metrics "${METRICS_JSON}" \
    '. + { metrics_path: $metrics_path, metrics: $metrics[0] }' \
    "${OUTPUTS_JSON}" > "${tmp}"
  mv "${tmp}" "${OUTPUTS_JSON}"
fi

echo "[${MODULE_NAME}] Step 7B staging complete"
echo "[${MODULE_NAME}] Step 7C metrics complete"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
