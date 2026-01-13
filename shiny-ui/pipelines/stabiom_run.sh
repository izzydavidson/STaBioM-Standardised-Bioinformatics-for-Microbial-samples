#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --config <path/to/config.json> [--force-overwrite] [--debug]"
  exit 1
}

CONFIG_PATH=""
FORCE_OVERWRITE_CLI="0"
DEBUG="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --force-overwrite) FORCE_OVERWRITE_CLI="1"; shift 1 ;;
    --debug) DEBUG="1"; shift 1 ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "${CONFIG_PATH}" ]]; then
  echo "ERROR: --config is required" >&2
  usage
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "ERROR: Config file not found: ${CONFIG_PATH}" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 3
fi

if [[ "${DEBUG}" == "1" ]]; then
  set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

sanitize_id() {
  echo "${1:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cd 'a-z0-9_-' \
    | sed 's/^-*//;s/-*$//'
}

require_field() {
  local jq_expr="$1"
  local friendly="$2"
  local val
  val="$(jq -r "${jq_expr} // empty" "${CONFIG_PATH}" | tr -d '\r\n' || true)"
  if [[ -z "${val}" || "${val}" == "null" ]]; then
    echo "ERROR: Missing required field: ${friendly}" >&2
    echo "       (Looked for jq: ${jq_expr})" >&2
    exit 4
  fi
}

PIPELINE_ID_RAW="$(jq -r '
  .pipeline_id
  // .pipelineId
  // .pipeline.id
  // .pipeline.pipeline_id
  // empty
' "${CONFIG_PATH}")"
PIPELINE_ID_RAW="$(printf "%s" "${PIPELINE_ID_RAW}" | tr -d '\r\n')"

if [[ -z "${PIPELINE_ID_RAW}" || "${PIPELINE_ID_RAW}" == "null" ]]; then
  echo "ERROR: Could not find pipeline_id in config. Expected one of:" >&2
  echo "  .pipeline_id | .pipelineId | .pipeline.id | .pipeline.pipeline_id" >&2
  exit 4
fi

PIPELINE_KEY="$(sanitize_id "${PIPELINE_ID_RAW}")"
PIPELINE_KEY="${PIPELINE_KEY//-/_}"

RUN_ID="$(jq -r '.run.run_id // .run_id // .runId // .run.id // empty' "${CONFIG_PATH}")"
RUN_ID="$(printf "%s" "${RUN_ID}" | tr -d '\r\n')"

WORK_DIR_RAW="$(jq -r '
  .run.work_dir
  // .work_dir
  // .workDir
  // .run.output_dir
  // .output_dir
  // .outputDir
  // empty
' "${CONFIG_PATH}")"
WORK_DIR_RAW="$(printf "%s" "${WORK_DIR_RAW}" | tr -d '\r\n')"

if [[ -z "${WORK_DIR_RAW}" || "${WORK_DIR_RAW}" == "null" ]]; then
  WORK_DIR_RAW="${REPO_ROOT}/runs"
fi

FORCE_OVERWRITE_CFG="$(jq -r '
  .run.force_overwrite
  // .force_overwrite
  // .forceOverwrite
  // empty
' "${CONFIG_PATH}")"
FORCE_OVERWRITE_CFG="$(printf "%s" "${FORCE_OVERWRITE_CFG}" | tr -d '\r\n')"

FORCE_OVERWRITE="0"
if [[ "${FORCE_OVERWRITE_CFG}" == "1" || "${FORCE_OVERWRITE_CFG}" == "true" ]]; then
  FORCE_OVERWRITE="1"
fi
if [[ "${FORCE_OVERWRITE_CLI}" == "1" ]]; then
  FORCE_OVERWRITE="1"
fi

INPUT_STYLE_RAW="$(jq -r '.input.style // .inputStyle // empty' "${CONFIG_PATH}")"
INPUT_STYLE_RAW="$(printf "%s" "${INPUT_STYLE_RAW}" | tr -d '\r\n')"
INPUT_STYLE_CANON="$(echo "${INPUT_STYLE_RAW}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9_-' )"
INPUT_STYLE_CANON="${INPUT_STYLE_CANON//-/_}"

case "${INPUT_STYLE_CANON}" in
  FAST5_DIR) require_field ".input.fast5_dir" "input.fast5_dir (path to directory of FAST5 files)" ;;
  FAST5_ARCHIVE) require_field ".input.fast5_archive" "input.fast5_archive (path to .zip or .tar.gz)" ;;
  FASTQ_SINGLE) require_field ".input.fastq_r1" "input.fastq_r1 (path to FASTQ R1 for single-end)" ;;
  FASTQ_PAIRED)
    require_field ".input.fastq_r1" "input.fastq_r1 (path to FASTQ R1)"
    require_field ".input.fastq_r2" "input.fastq_r2 (path to FASTQ R2)"
    ;;
  FASTQ_DIR_SINGLE) require_field ".input.fastq_dir" "input.fastq_dir (directory containing single-end FASTQs)" ;;
  FASTQ_DIR_PAIRED) require_field ".input.fastq_dir" "input.fastq_dir (directory containing paired-end FASTQs)" ;;
  "") echo "WARNING: No input.style provided. Continuing." >&2 ;;
  *) echo "WARNING: Unrecognized input.style '${INPUT_STYLE_RAW}' (canon: '${INPUT_STYLE_CANON}'). Continuing." >&2 ;;
esac

RUN_ID_RESOLVED="$(sanitize_id "${RUN_ID}")"
if [[ -z "${RUN_ID_RESOLVED}" ]]; then
  RUN_ID_RESOLVED="${PIPELINE_KEY}_$(date +%Y%m%d_%H%M%S)"
fi

WORK_DIR="${WORK_DIR_RAW%/}"
RUN_DIR="${WORK_DIR}/${RUN_ID_RESOLVED}"

if [[ -d "${RUN_DIR}" ]]; then
  if [[ "${FORCE_OVERWRITE}" == "1" ]]; then
    rm -rf "${RUN_DIR}"
  else
    echo "ERROR: Run directory already exists: ${RUN_DIR}" >&2
    echo "       Use --force-overwrite or set run.force_overwrite=1 to overwrite it." >&2
    exit 6
  fi
fi

mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/artifacts"
cp -f "${CONFIG_PATH}" "${RUN_DIR}/config.original.json"

EFFECTIVE_CONFIG_PATH="${RUN_DIR}/effective_config.json"
jq --arg run_dir "${RUN_DIR}" \
   --arg run_id "${RUN_ID_RESOLVED}" \
   --arg pipeline_key "${PIPELINE_KEY}" \
   --arg repo_root_container "${REPO_ROOT}" \
   '
   . + {
     "run_dir": $run_dir,
     "run_id_resolved": $run_id,
     "pipeline_key": $pipeline_key,
     "run": (
       (.run // {}) + {
         "run_dir": $run_dir,
         "run_id_resolved": $run_id,
         "repo_root_container": $repo_root_container
       }
     )
   }
   ' "${CONFIG_PATH}" > "${EFFECTIVE_CONFIG_PATH}"

MODULE_SCRIPT=""
case "${PIPELINE_KEY}" in
  lr_meta) MODULE_SCRIPT="${MODULES_DIR}/lr_meta.sh" ;;
  lr_amp)  MODULE_SCRIPT="${MODULES_DIR}/lr_amp.sh" ;;
  sr_meta) MODULE_SCRIPT="${MODULES_DIR}/sr_meta.sh" ;;
  sr_amp)  MODULE_SCRIPT="${MODULES_DIR}/sr_amp.sh" ;;
  *)
    echo "ERROR: No module mapping for pipeline_id '${PIPELINE_ID_RAW}' (normalized: '${PIPELINE_KEY}')" >&2
    exit 5
    ;;
esac

if [[ ! -f "${MODULE_SCRIPT}" ]]; then
  echo "ERROR: Module script not found: ${MODULE_SCRIPT}" >&2
  exit 5
fi

MODULE_LOG="${RUN_DIR}/logs/${PIPELINE_KEY}.log"

# Always write dispatch header into the module log so it's never a 0-byte mystery.
{
  echo "[dispatch] pipeline_id: ${PIPELINE_ID_RAW}"
  echo "[dispatch] pipeline_key: ${PIPELINE_KEY}"
  echo "[dispatch] input_style: ${INPUT_STYLE_RAW}"
  echo "[dispatch] run_dir: ${RUN_DIR}"
  echo "[dispatch] module: ${MODULE_SCRIPT}"
  echo "[dispatch] effective_config: ${EFFECTIVE_CONFIG_PATH}"
  echo "[dispatch] started_at: $(date -Iseconds)"
  echo
} | tee -a "${MODULE_LOG}" >/dev/null

set +e
bash "${MODULE_SCRIPT}" --config "${EFFECTIVE_CONFIG_PATH}" 2>&1 | tee -a "${MODULE_LOG}"
MODULE_EXIT="${PIPESTATUS[0]}"
set -e

{
  echo
  echo "[dispatch] ended_at: $(date -Iseconds)"
  echo "[dispatch] exit_code: ${MODULE_EXIT}"
} | tee -a "${MODULE_LOG}" >/dev/null

OUTPUTS_JSON="${RUN_DIR}/outputs.json"
jq -n \
  --arg pipeline_id "${PIPELINE_ID_RAW}" \
  --arg pipeline_key "${PIPELINE_KEY}" \
  --arg run_id "${RUN_ID_RESOLVED}" \
  --arg run_dir "${RUN_DIR}" \
  --arg module_log "${MODULE_LOG}" \
  --argjson success "$( [[ "${MODULE_EXIT}" == "0" ]] && echo true || echo false )" \
  --argjson exit_code "${MODULE_EXIT}" \
  '{
    pipeline_id: $pipeline_id,
    pipeline_key: $pipeline_key,
    run_id: $run_id,
    run_dir: $run_dir,
    success: $success,
    exit_code: $exit_code,
    logs: { module: $module_log },
    artifacts: {}
  }' > "${OUTPUTS_JSON}"

if [[ "${MODULE_EXIT}" != "0" ]]; then
  echo "ERROR: Module failed with exit code ${MODULE_EXIT}" >&2
  echo "       See log: ${MODULE_LOG}" >&2
  exit "${MODULE_EXIT}"
fi

echo "[done] Success. outputs.json: ${OUTPUTS_JSON}"
