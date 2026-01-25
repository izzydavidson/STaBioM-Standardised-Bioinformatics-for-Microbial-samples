#!/opt/homebrew/bin/bash
set -euo pipefail

MODULE_NAME="sr_meta"

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

count_fastq_lines() {
  local p="$1"
  if [[ -z "${p}" || "${p}" == "null" ]]; then
    echo "0"
    return 0
  fi
  require_file "${p}"
  if [[ "${p}" == *.gz ]]; then
    (gzip -cd "${p}" | wc -l 2>/dev/null || true) | tr -cd '0-9'
  else
    (wc -l < "${p}" 2>/dev/null || true) | tr -cd '0-9'
  fi
}

estimate_reads_from_lines() {
  local lines="$1"
  python3 - "$lines" <<'PY'
import sys
s = sys.argv[1]
s = "".join([c for c in s if c.isdigit()]) or "0"
lines = int(s)
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

fail_if_missing_files() {
  local missing=0
  for p in "$@"; do
    if [[ -z "${p}" || "${p}" == "null" ]]; then
      continue
    fi
    if [[ ! -f "${p}" ]]; then
      echo "ERROR: Expected file missing: ${p}" >&2
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]] || return 1
}

normalize_boolish() {
  local raw="${1:-}"
  local norm="false"
  if [[ -z "${raw}" || "${raw}" == "null" ]]; then
    echo "${norm}"; return 0
  fi
  case "$(printf "%s" "${raw}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    1|true|yes|y|on) norm="true" ;;
    0|false|no|n|off) norm="false" ;;
    auto) norm="auto" ;;
    *) norm="${raw}" ;;
  esac
  echo "${norm}"
}

# -----------------------------
# Validate input style / config
# -----------------------------
INPUT_STYLE="$(jq_first "${CONFIG_PATH}" '.input.style' '.inputs.style' '.input_style' '.inputs.input_style' || true)"
[[ -n "${INPUT_STYLE}" ]] || INPUT_STYLE="FASTQ_PAIRED"

if [[ "${INPUT_STYLE}" != "FASTQ_PAIRED" && "${INPUT_STYLE}" != "FASTQ_SINGLE" ]]; then
  echo "ERROR: ${MODULE_NAME} expects FASTQ_PAIRED or FASTQ_SINGLE, got: ${INPUT_STYLE}" >&2
  exit 2
fi

OUTPUT_DIR="$(jq_first "${CONFIG_PATH}" \
  '.run_dir' \
  '.run.run_dir' \
  '.run.work_dir' \
  '.output_dir' \
  '.run.output_dir' \
  '.outputs.output_dir' \
  '.output.output_dir' \
  || true)"
[[ -n "${OUTPUT_DIR}" ]] || { echo "ERROR: Could not determine output dir from config" >&2; exit 2; }
mkdir -p "${OUTPUT_DIR}"

RUN_ID="$(jq_first "${CONFIG_PATH}" '.run_id_resolved' '.run.run_id' '.run_id' '.id' '.run.id' || true)"
PIPELINE_ID="$(jq_first "${CONFIG_PATH}" '.pipeline_id' '.run.pipeline_id' '.pipeline.id' '.pipeline_key' || true)"
SPECIMEN_RAW="$(jq_first "${CONFIG_PATH}" '.specimen' '.sample_type' '.input.sample_type' '.inputs.sample_type' '.run.sample_type' '.run.sample_type_resolved' || true)"
SPECIMEN_NORM="$(printf "%s" "${SPECIMEN_RAW:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
[[ -n "${SPECIMEN_NORM}" ]] || SPECIMEN_NORM="other"

THREADS="$(jq_first_int "${CONFIG_PATH}" '.resources.threads' '.resources.n_threads' '.threads' || true)"
[[ -n "${THREADS}" ]] || THREADS="1"
if [[ "${THREADS}" -lt 1 ]]; then THREADS="1"; fi

SAMPLE_ID="$(jq_first "${CONFIG_PATH}" '.sample_id' '.kraken2.sample_id' '.fastp.sample_id' '.cutadapt.sample_id' || true)"
[[ -n "${SAMPLE_ID}" ]] || SAMPLE_ID="sample1"

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

REMOVE_HOST_RAW="$(jq_first "${CONFIG_PATH}" \
  '.params.common.remove_host' \
  '.params.remove_host' \
  '.common.remove_host' \
  '.remove_host' \
  || true)"
REMOVE_HOST_NORM="$(normalize_boolish "${REMOVE_HOST_RAW}")"

# -----------------------------
# Layout: <run_dir>/sr_meta/...
# -----------------------------
MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
FASTQ_STAGE_DIR="${MODULE_OUT_DIR}/inputs/fastq"
REF_STAGE_DIR="${MODULE_OUT_DIR}/inputs/reference"
RESULTS_DIR="${MODULE_OUT_DIR}/results"
LOGS_DIR="${MODULE_OUT_DIR}/logs"
STEPS_JSON="${MODULE_OUT_DIR}/steps.json"
mkdir -p "${FASTQ_STAGE_DIR}" "${REF_STAGE_DIR}" "${RESULTS_DIR}" "${LOGS_DIR}"

STAGED_R1="${FASTQ_STAGE_DIR}/$(basename "${FASTQ_R1_SRC}")"
STAGED_R2=""
rm -f "${STAGED_R1}"
cp -f "${FASTQ_R1_SRC}" "${STAGED_R1}"

if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
  STAGED_R2="${FASTQ_STAGE_DIR}/$(basename "${FASTQ_R2_SRC}")"
  rm -f "${STAGED_R2}"
  cp -f "${FASTQ_R2_SRC}" "${STAGED_R2}"
fi

# -----------------------------
# outputs.json base
# -----------------------------
OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"
jq -n \
  --arg mod "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg sample_id "${SAMPLE_ID}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg specimen "${SPECIMEN_RAW:-}" \
  --arg fastq_r1 "${STAGED_R1}" \
  --arg fastq_r2 "${STAGED_R2}" \
  '{
    module_name: $mod,
    pipeline_id: $pipeline_id,
    run_id: $run_id,
    specimen: ($specimen | select(length>0) // null),
    sample_id: $sample_id,
    input_style: $input_style,
    inputs: {
      fastq_r1: $fastq_r1,
      fastq_r2: ($fastq_r2 | select(length>0) // null)
    }
  }' > "${OUTPUTS_JSON}"

# -----------------------------
# Metrics (raw input)
# -----------------------------
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
    steps_append "${STEPS_JSON}" "fastqc" "succeeded" "fastqc completed" "${FASTQC_BIN}" "fastqc" "${ec}" "${started}" "${ended}"
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
    steps_append "${STEPS_JSON}" "multiqc" "succeeded" "multiqc completed" "${MULTIQC_BIN}" "multiqc" "${ec}" "${started}" "${ended}"
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
# Demultiplex (optional): cutadapt inline-barcode demux
# -----------------------------
CUTADAPT_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.cutadapt_bin' 'cutadapt')"

DEMUX_ENABLED_RAW="$(jq_first "${CONFIG_PATH}" '.cutadapt.demux.enabled' '.cutadapt.demux_enabled' '.demux.enabled' '.demux_enabled' || true)"
DEMUX_ENABLED="$(normalize_boolish "${DEMUX_ENABLED_RAW}")"

BARCODES_R1_FASTA_HOST="$(jq_first "${CONFIG_PATH}" '.cutadapt.demux.barcodes_r1_fasta' '.cutadapt.demux.barcodes_fasta_r1' '.demux.barcodes_r1_fasta' || true)"
BARCODES_R2_FASTA_HOST="$(jq_first "${CONFIG_PATH}" '.cutadapt.demux.barcodes_r2_fasta' '.cutadapt.demux.barcodes_fasta_r2' '.demux.barcodes_r2_fasta' || true)"
DEMUX_DISCARD_UNTRIMMED_RAW="$(jq_first "${CONFIG_PATH}" '.cutadapt.demux.discard_untrimmed' '.demux.discard_untrimmed' || true)"
DEMUX_DISCARD_UNTRIMMED="$(normalize_boolish "${DEMUX_DISCARD_UNTRIMMED_RAW}")"
[[ "${DEMUX_DISCARD_UNTRIMMED}" == "true" || "${DEMUX_DISCARD_UNTRIMMED}" == "false" ]] || DEMUX_DISCARD_UNTRIMMED="true"

CUTADAPT_LOG="${LOGS_DIR}/cutadapt_demux.log"
CUTADAPT_DIR="${RESULTS_DIR}/cutadapt"
DEMUX_DIR="${CUTADAPT_DIR}/demux"
mkdir -p "${CUTADAPT_DIR}"

declare -a UNITS=()
declare -A UNIT_R1=()
declare -A UNIT_R2=()

STAGED_BARCODES_R1=""
STAGED_BARCODES_R2=""

if [[ "${DEMUX_ENABLED}" == "true" ]]; then
  if [[ -z "${CUTADAPT_BIN}" ]]; then
    echo "ERROR: Demux enabled but cutadapt not found. Install cutadapt or set tools.cutadapt_bin." >&2
    exit 2
  fi

  mkdir -p "${DEMUX_DIR}"

  if [[ -z "${BARCODES_R1_FASTA_HOST}" || "${BARCODES_R1_FASTA_HOST}" == "null" ]]; then
    echo "ERROR: cutadapt.demux.enabled=true but cutadapt.demux.barcodes_r1_fasta is empty." >&2
    exit 2
  fi
  require_file "${BARCODES_R1_FASTA_HOST}"
  STAGED_BARCODES_R1="${REF_STAGE_DIR}/$(basename "${BARCODES_R1_FASTA_HOST}")"
  rm -f "${STAGED_BARCODES_R1}"
  cp -f "${BARCODES_R1_FASTA_HOST}" "${STAGED_BARCODES_R1}"

  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    if [[ -n "${BARCODES_R2_FASTA_HOST}" && "${BARCODES_R2_FASTA_HOST}" != "null" ]]; then
      require_file "${BARCODES_R2_FASTA_HOST}"
      STAGED_BARCODES_R2="${REF_STAGE_DIR}/$(basename "${BARCODES_R2_FASTA_HOST}")"
      rm -f "${STAGED_BARCODES_R2}"
      cp -f "${BARCODES_R2_FASTA_HOST}" "${STAGED_BARCODES_R2}"
    fi
  fi

  started="$(iso_now)"
  set +e
  {
    echo "[cutadapt_demux] enabled=true"
    echo "[cutadapt_demux] discard_untrimmed=${DEMUX_DISCARD_UNTRIMMED}"
    echo "[cutadapt_demux] barcodes_r1=${STAGED_BARCODES_R1}"
    echo "[cutadapt_demux] barcodes_r2=${STAGED_BARCODES_R2:-<none>}"
  } >>"${CUTADAPT_LOG}" 2>&1

  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    if [[ -n "${STAGED_BARCODES_R2}" ]]; then
      if [[ "${DEMUX_DISCARD_UNTRIMMED}" == "true" ]]; then
        "${CUTADAPT_BIN}" --cores "${THREADS}" \
          -g "file:${STAGED_BARCODES_R1}" -G "file:${STAGED_BARCODES_R2}" \
          --discard-untrimmed \
          -o "${DEMUX_DIR}/{name}_R1.fastq.gz" -p "${DEMUX_DIR}/{name}_R2.fastq.gz" \
          "${STAGED_R1}" "${STAGED_R2}" >>"${CUTADAPT_LOG}" 2>&1
      else
        "${CUTADAPT_BIN}" --cores "${THREADS}" \
          -g "file:${STAGED_BARCODES_R1}" -G "file:${STAGED_BARCODES_R2}" \
          -o "${DEMUX_DIR}/{name}_R1.fastq.gz" -p "${DEMUX_DIR}/{name}_R2.fastq.gz" \
          "${STAGED_R1}" "${STAGED_R2}" >>"${CUTADAPT_LOG}" 2>&1
      fi
    else
      if [[ "${DEMUX_DISCARD_UNTRIMMED}" == "true" ]]; then
        "${CUTADAPT_BIN}" --cores "${THREADS}" \
          -g "file:${STAGED_BARCODES_R1}" \
          --discard-untrimmed \
          -o "${DEMUX_DIR}/{name}_R1.fastq.gz" -p "${DEMUX_DIR}/{name}_R2.fastq.gz" \
          "${STAGED_R1}" "${STAGED_R2}" >>"${CUTADAPT_LOG}" 2>&1
      else
        "${CUTADAPT_BIN}" --cores "${THREADS}" \
          -g "file:${STAGED_BARCODES_R1}" \
          -o "${DEMUX_DIR}/{name}_R1.fastq.gz" -p "${DEMUX_DIR}/{name}_R2.fastq.gz" \
          "${STAGED_R1}" "${STAGED_R2}" >>"${CUTADAPT_LOG}" 2>&1
      fi
    fi
  else
    if [[ "${DEMUX_DISCARD_UNTRIMMED}" == "true" ]]; then
      "${CUTADAPT_BIN}" --cores "${THREADS}" \
        -g "file:${STAGED_BARCODES_R1}" \
        --discard-untrimmed \
        -o "${DEMUX_DIR}/{name}.fastq.gz" \
        "${STAGED_R1}" >>"${CUTADAPT_LOG}" 2>&1
    else
      "${CUTADAPT_BIN}" --cores "${THREADS}" \
        -g "file:${STAGED_BARCODES_R1}" \
        -o "${DEMUX_DIR}/{name}.fastq.gz" \
        "${STAGED_R1}" >>"${CUTADAPT_LOG}" 2>&1
    fi
  fi

  DEMUX_EC=$?
  set -e
  ended="$(iso_now)"

  if [[ "${DEMUX_EC}" -ne 0 ]]; then
    steps_append "${STEPS_JSON}" "cutadapt_demux" "failed" "cutadapt demultiplex failed (see logs/cutadapt_demux.log)" "${CUTADAPT_BIN}" "cutadapt demux" "${DEMUX_EC}" "${started}" "${ended}"
    exit 3
  else
    steps_append "${STEPS_JSON}" "cutadapt_demux" "succeeded" "cutadapt demultiplex completed" "${CUTADAPT_BIN}" "cutadapt demux" "0" "${started}" "${ended}"
  fi

  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    shopt -s nullglob
    r1s=( "${DEMUX_DIR}"/*_R1.fastq.gz )
    shopt -u nullglob
    if [[ "${#r1s[@]}" -eq 0 ]]; then
      echo "ERROR: Demux produced zero samples in ${DEMUX_DIR}" >&2
      exit 3
    fi
    for r1 in "${r1s[@]}"; do
      name="$(basename "${r1}" | sed -E 's/_R1\.fastq\.gz$//')"
      r2="${DEMUX_DIR}/${name}_R2.fastq.gz"
      if [[ ! -f "${r2}" ]]; then
        echo "ERROR: Demux missing mate for ${name}: ${r2}" >&2
        exit 3
      fi
      UNITS+=( "${name}" )
      UNIT_R1["${name}"]="${r1}"
      UNIT_R2["${name}"]="${r2}"
    done
  else
    shopt -s nullglob
    ses=( "${DEMUX_DIR}"/*.fastq.gz )
    shopt -u nullglob
    if [[ "${#ses[@]}" -eq 0 ]]; then
      echo "ERROR: Demux produced zero samples in ${DEMUX_DIR}" >&2
      exit 3
    fi
    for se in "${ses[@]}"; do
      name="$(basename "${se}" | sed -E 's/\.fastq\.gz$//')"
      UNITS+=( "${name}" )
      UNIT_R1["${name}"]="${se}"
    done
  fi
else
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "cutadapt_demux" "skipped" "Demultiplex disabled" "" "" "0" "${started}" "${ended}"
  UNITS+=( "${SAMPLE_ID}" )
  UNIT_R1["${SAMPLE_ID}"]="${STAGED_R1}"
  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    UNIT_R2["${SAMPLE_ID}"]="${STAGED_R2}"
  fi
fi

tmp="${OUTPUTS_JSON}.tmp"
jq --arg cutadapt_dir "${CUTADAPT_DIR}" \
   --arg cutadapt_log "${CUTADAPT_LOG}" \
   --arg demux_enabled "${DEMUX_ENABLED}" \
   --arg demux_dir "${DEMUX_DIR}" \
   --arg barcodes_r1 "${STAGED_BARCODES_R1}" \
   --arg barcodes_r2 "${STAGED_BARCODES_R2}" \
   '. + {cutadapt: {dir:$cutadapt_dir, log:$cutadapt_log, demux_enabled:$demux_enabled, demux_dir:($demux_dir|select(length>0)//null), barcodes_r1:($barcodes_r1|select(length>0)//null), barcodes_r2:($barcodes_r2|select(length>0)//null)}}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# Trimming / filtering: fastp (always on)
# -----------------------------
FASTP_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.fastp_bin' 'fastp')"
if [[ -z "${FASTP_BIN}" ]]; then
  echo "ERROR: fastp not found. Install fastp in the SR container or set tools.fastp_bin." >&2
  exit 2
fi

FASTP_DIR="${RESULTS_DIR}/fastp"
FASTP_LOG="${LOGS_DIR}/fastp.log"
mkdir -p "${FASTP_DIR}"

FASTP_Q_CUTOFF="$(jq_first_int "${CONFIG_PATH}" '.fastp.q_cutoff' '.fastp.trim.q_cutoff' '.cutadapt.trim.q_cutoff' '.params.common.min_qscore' || true)"
[[ -n "${FASTP_Q_CUTOFF}" ]] || FASTP_Q_CUTOFF="10"

FASTP_MIN_LEN="$(jq_first_int "${CONFIG_PATH}" '.fastp.min_len' '.fastp.trim.min_len' '.cutadapt.trim.min_len' || true)"
[[ -n "${FASTP_MIN_LEN}" ]] || FASTP_MIN_LEN="50"

FASTP_MAX_LEN="$(jq_first_int "${CONFIG_PATH}" '.fastp.max_len' '.fastp.trim.max_len' '.cutadapt.trim.max_len' || true)"
[[ -n "${FASTP_MAX_LEN}" ]] || FASTP_MAX_LEN="0"

FASTP_ADAPTER_R1="$(jq_first "${CONFIG_PATH}" '.fastp.adapter_r1' '.fastp.adapters.r1' '.cutadapt.trim.adapter_fwd' '.cutadapt.trim.adapter_r1' '.cutadapt.adapters.r1' || true)"
FASTP_ADAPTER_R2="$(jq_first "${CONFIG_PATH}" '.fastp.adapter_r2' '.fastp.adapters.r2' '.cutadapt.trim.adapter_rev' '.cutadapt.trim.adapter_r2' '.cutadapt.adapters.r2' || true)"

FASTP_GZIP_LEVEL="$(jq_first_int "${CONFIG_PATH}" '.fastp.gzip_level' '.fastp.compression' || true)"
[[ -n "${FASTP_GZIP_LEVEL}" ]] || FASTP_GZIP_LEVEL="4"
if [[ "${FASTP_GZIP_LEVEL}" -lt 1 ]]; then FASTP_GZIP_LEVEL="1"; fi
if [[ "${FASTP_GZIP_LEVEL}" -gt 9 ]]; then FASTP_GZIP_LEVEL="9"; fi

TRIM_DIR="${FASTP_DIR}/trimmed"
REPORTS_DIR="${FASTP_DIR}/reports"
mkdir -p "${TRIM_DIR}" "${REPORTS_DIR}"

declare -A TRIMMED_R1=()
declare -A TRIMMED_R2=()
declare -A FASTP_HTML=()
declare -A FASTP_JSON=()

started="$(iso_now)"
set +e

{
  echo "[fastp] q_cutoff=${FASTP_Q_CUTOFF} min_len=${FASTP_MIN_LEN} max_len=${FASTP_MAX_LEN} threads=${THREADS} gzip_level=${FASTP_GZIP_LEVEL}"
  echo "[fastp] adapter_r1='${FASTP_ADAPTER_R1:-}' adapter_r2='${FASTP_ADAPTER_R2:-}'"
} >>"${FASTP_LOG}" 2>&1

FASTP_EC=0
for u in "${UNITS[@]}"; do
  in1="${UNIT_R1[${u}]}"
  in2="${UNIT_R2[${u}]:-}"

  out1="${TRIM_DIR}/${u}_trimmed_R1.fastq.gz"
  out2=""
  html="${REPORTS_DIR}/${u}.fastp.html"
  json="${REPORTS_DIR}/${u}.fastp.json"

  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    out2="${TRIM_DIR}/${u}_trimmed_R2.fastq.gz"
    echo "[fastp] unit=${u} paired" >>"${FASTP_LOG}" 2>&1

    args=( -i "${in1}" -I "${in2}" -o "${out1}" -O "${out2}" -w "${THREADS}" -z "${FASTP_GZIP_LEVEL}" )
    args+=( --qualified_quality_phred "${FASTP_Q_CUTOFF}" --length_required "${FASTP_MIN_LEN}" )
    if [[ "${FASTP_MAX_LEN}" -gt 0 ]]; then args+=( --length_limit "${FASTP_MAX_LEN}" ); fi
    args+=( --html "${html}" --json "${json}" )

    if [[ -n "${FASTP_ADAPTER_R1}" ]]; then args+=( --adapter_sequence "${FASTP_ADAPTER_R1}" ); fi
    if [[ -n "${FASTP_ADAPTER_R2}" ]]; then args+=( --adapter_sequence_r2 "${FASTP_ADAPTER_R2}" ); fi
    if [[ -z "${FASTP_ADAPTER_R1}" && -z "${FASTP_ADAPTER_R2}" ]]; then
      args+=( --detect_adapter_for_pe )
    fi

    "${FASTP_BIN}" "${args[@]}" >>"${FASTP_LOG}" 2>&1
    ec=$?
  else
    echo "[fastp] unit=${u} single" >>"${FASTP_LOG}" 2>&1

    args=( -i "${in1}" -o "${out1}" -w "${THREADS}" -z "${FASTP_GZIP_LEVEL}" )
    args+=( --qualified_quality_phred "${FASTP_Q_CUTOFF}" --length_required "${FASTP_MIN_LEN}" )
    if [[ "${FASTP_MAX_LEN}" -gt 0 ]]; then args+=( --length_limit "${FASTP_MAX_LEN}" ); fi
    args+=( --html "${html}" --json "${json}" )

    if [[ -n "${FASTP_ADAPTER_R1}" ]]; then args+=( --adapter_sequence "${FASTP_ADAPTER_R1}" ); fi

    "${FASTP_BIN}" "${args[@]}" >>"${FASTP_LOG}" 2>&1
    ec=$?
  fi

  if [[ $ec -ne 0 ]]; then
    FASTP_EC=$ec
    break
  fi

  TRIMMED_R1["${u}"]="${out1}"
  FASTP_HTML["${u}"]="${html}"
  FASTP_JSON["${u}"]="${json}"
  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    TRIMMED_R2["${u}"]="${out2}"
  fi
done

set -e
ended="$(iso_now)"

if [[ "${FASTP_EC}" -ne 0 ]]; then
  steps_append "${STEPS_JSON}" "fastp_trim_filter" "failed" "fastp trim/filter failed (see logs/fastp.log)" "${FASTP_BIN}" "fastp" "${FASTP_EC}" "${started}" "${ended}"
  exit 3
else
  steps_append "${STEPS_JSON}" "fastp_trim_filter" "succeeded" "fastp trimming/filtering completed" "${FASTP_BIN}" "fastp" "0" "${started}" "${ended}"
fi

FASTP_UNITS_JSON="${FASTP_DIR}/fastp_units.json"
python3 - "${FASTP_UNITS_JSON}" "${INPUT_STYLE}" "${UNITS[@]}" <<'PY'
import json, sys
out = sys.argv[1]
input_style = sys.argv[2]
units = sys.argv[3:]
arr = []
for u in units:
    arr.append({"unit": u})
with open(out, "w", encoding="utf-8") as f:
    json.dump(arr, f, indent=2)
PY

tmp="${OUTPUTS_JSON}.tmp"
jq --arg fastp_dir "${FASTP_DIR}" \
   --arg fastp_log "${FASTP_LOG}" \
   --arg fastp_trim_dir "${TRIM_DIR}" \
   --arg fastp_reports_dir "${REPORTS_DIR}" \
   --arg fastp_units_json "${FASTP_UNITS_JSON}" \
   '. + {fastp:{dir:$fastp_dir, log:$fastp_log, trimmed_dir:$fastp_trim_dir, reports_dir:$fastp_reports_dir, units_json:$fastp_units_json}}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# Host depletion (optional): minimap2 + samtools
# -----------------------------
HOSTDEP_DIR="${RESULTS_DIR}/host_depletion"
mkdir -p "${HOSTDEP_DIR}"
HOSTDEP_LOG="${LOGS_DIR}/host_depletion.log"

declare -A NONHOST_R1=()
declare -A NONHOST_R2=()

if [[ "${REMOVE_HOST_NORM}" != "true" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "host_depletion" "skipped" "Host depletion disabled (params.common.remove_host != 1/true)" "" "" "0" "${started}" "${ended}"
  for u in "${UNITS[@]}"; do
    NONHOST_R1["${u}"]="${TRIMMED_R1[${u}]}"
    if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
      NONHOST_R2["${u}"]="${TRIMMED_R2[${u}]}"
    fi
  done
else
  MINIMAP2_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.minimap2_bin' 'minimap2')"
  SAMTOOLS_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.samtools_bin' 'samtools')"
  HUMAN_MMI="$(jq_first "${CONFIG_PATH}" '.tools.minimap2.human_mmi' '.tools.human_mmi' '.minimap2.human_mmi' '.host_depletion.human_mmi' || true)"

  if [[ -z "${MINIMAP2_BIN}" || -z "${SAMTOOLS_BIN}" ]]; then
    echo "ERROR: minimap2 and samtools are required for host depletion. Install them or set tools.minimap2_bin/tools.samtools_bin." >&2
    exit 2
  fi
  [[ -n "${HUMAN_MMI}" ]] || { echo "ERROR: Missing human minimap2 index path. Set tools.minimap2.human_mmi (a .mmi file)." >&2; exit 2; }
  require_file "${HUMAN_MMI}"

  # Build minimap2 args - include -I for split index loading if MINIMAP2_SPLIT_INDEX is set
  # This allows running on memory-constrained systems (e.g., 8GB Docker memory)
  MINIMAP2_SPLIT_SIZE="${MINIMAP2_SPLIT_INDEX:-}"
  MINIMAP2_EXTRA_ARGS=()
  if [[ -n "${MINIMAP2_SPLIT_SIZE}" ]]; then
    MINIMAP2_EXTRA_ARGS+=( -I "${MINIMAP2_SPLIT_SIZE}" )
    echo "[host_depletion] Using minimap2 split-index mode: -I ${MINIMAP2_SPLIT_SIZE}" >>"${HOSTDEP_LOG}" 2>&1
  fi

  started="$(iso_now)"
  set +e
  for u in "${UNITS[@]}"; do
    echo "[host_depletion] unit=${u}" >>"${HOSTDEP_LOG}" 2>&1
    if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
      in1="${TRIMMED_R1[${u}]}"
      in2="${TRIMMED_R2[${u}]}"
      out1="${HOSTDEP_DIR}/${u}_nonhost_R1.fastq.gz"
      out2="${HOSTDEP_DIR}/${u}_nonhost_R2.fastq.gz"
      bam="${HOSTDEP_DIR}/${u}_vs_human.bam"

      "${MINIMAP2_BIN}" "${MINIMAP2_EXTRA_ARGS[@]}" -t "${THREADS}" -ax sr "${HUMAN_MMI}" "${in1}" "${in2}" 2>>"${HOSTDEP_LOG}" \
        | "${SAMTOOLS_BIN}" view -b -o "${bam}" - >>"${HOSTDEP_LOG}" 2>&1
      ec=$?
      if [[ $ec -ne 0 ]]; then
        set -e
        ended="$(iso_now)"
        steps_append "${STEPS_JSON}" "host_depletion" "failed" "minimap2->samtools failed (see logs/host_depletion.log)" "minimap2/samtools" "minimap2 | samtools view" "${ec}" "${started}" "${ended}"
        exit 3
      fi

      "${SAMTOOLS_BIN}" fastq -f 12 -F 256 \
        -1 >(gzip -c > "${out1}") \
        -2 >(gzip -c > "${out2}") \
        -0 /dev/null -s /dev/null -n \
        "${bam}" >>"${HOSTDEP_LOG}" 2>&1
      ec=$?
      if [[ $ec -ne 0 ]]; then
        set -e
        ended="$(iso_now)"
        steps_append "${STEPS_JSON}" "host_depletion" "failed" "samtools fastq failed (see logs/host_depletion.log)" "samtools" "samtools fastq -f 12" "${ec}" "${started}" "${ended}"
        exit 3
      fi

      NONHOST_R1["${u}"]="${out1}"
      NONHOST_R2["${u}"]="${out2}"
    else
      in1="${TRIMMED_R1[${u}]}"
      out1="${HOSTDEP_DIR}/${u}_nonhost.fastq.gz"
      bam="${HOSTDEP_DIR}/${u}_vs_human.bam"

      "${MINIMAP2_BIN}" "${MINIMAP2_EXTRA_ARGS[@]}" -t "${THREADS}" -ax sr "${HUMAN_MMI}" "${in1}" 2>>"${HOSTDEP_LOG}" \
        | "${SAMTOOLS_BIN}" view -b -o "${bam}" - >>"${HOSTDEP_LOG}" 2>&1
      ec=$?
      if [[ $ec -ne 0 ]]; then
        set -e
        ended="$(iso_now)"
        steps_append "${STEPS_JSON}" "host_depletion" "failed" "minimap2->samtools failed (see logs/host_depletion.log)" "minimap2/samtools" "minimap2 | samtools view" "${ec}" "${started}" "${ended}"
        exit 3
      fi

      "${SAMTOOLS_BIN}" fastq -f 4 -F 256 "${bam}" 2>>"${HOSTDEP_LOG}" | gzip -c > "${out1}"
      ec=$?
      if [[ $ec -ne 0 ]]; then
        set -e
        ended="$(iso_now)"
        steps_append "${STEPS_JSON}" "host_depletion" "failed" "samtools fastq failed (see logs/host_depletion.log)" "samtools" "samtools fastq -f 4" "${ec}" "${started}" "${ended}"
        exit 3
      fi

      NONHOST_R1["${u}"]="${out1}"
    fi
  done
  set -e
  ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "host_depletion" "succeeded" "Host depletion completed (minimap2 + samtools)" "minimap2/samtools" "minimap2 + samtools" "0" "${started}" "${ended}"
fi

tmp="${OUTPUTS_JSON}.tmp"
jq --arg host_depletion_dir "${HOSTDEP_DIR}" --arg host_depletion_log "${HOSTDEP_LOG}" --arg remove_host "${REMOVE_HOST_NORM}" \
  '. + {host_depletion:{enabled:$remove_host, dir:$host_depletion_dir, log:$host_depletion_log}}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# Kraken2 taxonomy classification
# -----------------------------
KRAKEN2_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.kraken2_bin' 'kraken2')"
KRAKEN2_DB="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.db' '.tools.kraken2.db_classify' '.kraken2.db' '.kraken2.db_classify' || true)"
if [[ -z "${KRAKEN2_BIN}" ]]; then
  echo "ERROR: kraken2 not found. Install kraken2 or set tools.kraken2_bin." >&2
  exit 2
fi
[[ -n "${KRAKEN2_DB}" ]] || { echo "ERROR: Missing kraken2 DB path. Set tools.kraken2.db (or tools.kraken2.db_classify)." >&2; exit 2; }
if [[ ! -d "${KRAKEN2_DB}" ]]; then
  echo "ERROR: Kraken2 DB directory not found: ${KRAKEN2_DB}" >&2
  exit 2
fi

# Read memory_mapping option for low-RAM systems (uses disk I/O instead of loading DB into RAM)
KRAKEN2_MEMORY_MAPPING_RAW="$(jq_first "${CONFIG_PATH}" '.params.kraken2.memory_mapping' '.kraken2.memory_mapping' || true)"
KRAKEN2_MEMORY_MAPPING="$(normalize_boolish "${KRAKEN2_MEMORY_MAPPING_RAW}")"

KRAKEN_DIR="${RESULTS_DIR}/kraken2"
mkdir -p "${KRAKEN_DIR}"
KRAKEN_LOG="${LOGS_DIR}/kraken2.log"

# Build kraken2 extra args (e.g., --memory-mapping for low-RAM systems)
KRAKEN2_EXTRA_ARGS=()
if [[ "${KRAKEN2_MEMORY_MAPPING}" == "true" ]]; then
  KRAKEN2_EXTRA_ARGS+=( --memory-mapping )
  echo "[kraken2] memory-mapping enabled (uses disk I/O instead of loading DB into RAM)" >>"${KRAKEN_LOG}" 2>&1
fi

declare -A KRAKEN_REPORT=()
declare -A KRAKEN_OUTPUT=()

started="$(iso_now)"
set +e
for u in "${UNITS[@]}"; do
  echo "[kraken2] unit=${u}" >>"${KRAKEN_LOG}" 2>&1
  report="${KRAKEN_DIR}/${u}.report.tsv"
  out="${KRAKEN_DIR}/${u}.kraken.tsv"

  if [[ "${INPUT_STYLE}" == "FASTQ_PAIRED" ]]; then
    r1="${NONHOST_R1[${u}]}"
    r2="${NONHOST_R2[${u}]}"
    "${KRAKEN2_BIN}" --db "${KRAKEN2_DB}" "${KRAKEN2_EXTRA_ARGS[@]}" --threads "${THREADS}" --paired --gzip-compressed \
      --report "${report}" \
      --output "${out}" \
      "${r1}" "${r2}" >>"${KRAKEN_LOG}" 2>&1
  else
    r1="${NONHOST_R1[${u}]}"
    "${KRAKEN2_BIN}" --db "${KRAKEN2_DB}" "${KRAKEN2_EXTRA_ARGS[@]}" --threads "${THREADS}" --gzip-compressed \
      --report "${report}" \
      --output "${out}" \
      "${r1}" >>"${KRAKEN_LOG}" 2>&1
  fi

  ec=$?
  if [[ $ec -ne 0 ]]; then
    set -e
    ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "kraken2" "failed" "kraken2 failed (see logs/kraken2.log)" "${KRAKEN2_BIN}" "kraken2 --report --output" "${ec}" "${started}" "${ended}"
    exit 3
  fi

  KRAKEN_REPORT["${u}"]="${report}"
  KRAKEN_OUTPUT["${u}"]="${out}"
done
set -e
ended="$(iso_now)"
steps_append "${STEPS_JSON}" "kraken2" "succeeded" "kraken2 classification completed" "${KRAKEN2_BIN}" "kraken2" "0" "${started}" "${ended}"

tmp="${OUTPUTS_JSON}.tmp"
jq --arg kraken2_dir "${KRAKEN_DIR}" --arg kraken2_log "${KRAKEN_LOG}" '. + {kraken2:{dir:$kraken2_dir, log:$kraken2_log}}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

# -----------------------------
# VALENCIA (kraken-report driven; gated by specimen)
# -----------------------------
VALENCIA_ENABLED_RAW="$(jq_first "${CONFIG_PATH}" '.valencia.enabled' '.qiime2.valencia.enabled' '.valencia_enabled' '.tools.valencia.enabled' || true)"
VALENCIA_ENABLED_NORM="$(normalize_boolish "${VALENCIA_ENABLED_RAW}")"
VALENCIA_MODE_RAW="$(jq_first "${CONFIG_PATH}" '.valencia.mode' '.qiime2.valencia.mode' || true)"
VALENCIA_MODE_NORM="$(printf "%s" "${VALENCIA_MODE_RAW:-auto}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
[[ -n "${VALENCIA_MODE_NORM}" ]] || VALENCIA_MODE_NORM="auto"

VALENCIA_CENTROIDS_HOST="$(jq_first "${CONFIG_PATH}" '.valencia.centroids_csv' '.qiime2.valencia.centroids_csv' '.tools.valencia.centroids_csv' || true)"

VALENCIA_DIR="${RESULTS_DIR}/valencia"
VALENCIA_LOG="${LOGS_DIR}/valencia.log"
mkdir -p "${VALENCIA_DIR}"

VALENCIA_SHOULD_RUN="no"
if [[ "${VALENCIA_ENABLED_NORM}" == "true" ]]; then
  VALENCIA_SHOULD_RUN="yes"
elif [[ "${VALENCIA_ENABLED_NORM}" == "auto" || "${VALENCIA_MODE_NORM}" == "auto" ]]; then
  if [[ "${SPECIMEN_NORM}" == "vaginal" ]]; then
    VALENCIA_SHOULD_RUN="yes"
  fi
fi

STAGED_VALENCIA_CENTROIDS=""
if [[ "${VALENCIA_SHOULD_RUN}" == "yes" ]]; then
  if [[ -z "${VALENCIA_CENTROIDS_HOST}" || "${VALENCIA_CENTROIDS_HOST}" == "null" ]]; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "valencia" "failed" "VALENCIA enabled but centroids_csv missing in config (valencia.centroids_csv)" "" "" "2" "${started}" "${ended}"
    echo "ERROR: VALENCIA enabled but centroids_csv missing (valencia.centroids_csv)." >&2
    exit 2
  fi
  require_file "${VALENCIA_CENTROIDS_HOST}"
  STAGED_VALENCIA_CENTROIDS="${REF_STAGE_DIR}/$(basename "${VALENCIA_CENTROIDS_HOST}")"
  rm -f "${STAGED_VALENCIA_CENTROIDS}"
  cp -f "${VALENCIA_CENTROIDS_HOST}" "${STAGED_VALENCIA_CENTROIDS}"
fi

if [[ "${VALENCIA_SHOULD_RUN}" != "yes" ]]; then
  started="$(iso_now)"; ended="$(iso_now)"
  steps_append "${STEPS_JSON}" "valencia" "skipped" "VALENCIA skipped (enabled=${VALENCIA_ENABLED_NORM}, specimen=${SPECIMEN_RAW:-})" "" "" "0" "${started}" "${ended}"
else
  # Check if pandas is available (required for VALENCIA)
  if ! python3 -c "import pandas" 2>/dev/null; then
    started="$(iso_now)"; ended="$(iso_now)"
    steps_append "${STEPS_JSON}" "valencia" "skipped" "VALENCIA skipped (pandas not installed - run: pip3 install pandas matplotlib)" "" "" "0" "${started}" "${ended}"
    echo "[valencia] WARN: pandas not installed, skipping VALENCIA. Install with: pip3 install pandas matplotlib" >&2
  else
    VALENCIA_PLOTS_DIR="${VALENCIA_DIR}/plots"
    mkdir -p "${VALENCIA_PLOTS_DIR}"

    started="$(iso_now)"
    set +e

    python3 - "${STAGED_VALENCIA_CENTROIDS}" "${VALENCIA_DIR}" "${VALENCIA_PLOTS_DIR}" "${SPECIMEN_NORM}" "${VALENCIA_LOG}" "${KRAKEN_DIR}" <<'PY'
import os, sys, re
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

centroids_csv, out_dir, plots_dir, specimen_norm, log_path, kraken_dir = sys.argv[1:]
os.makedirs(out_dir, exist_ok=True)
os.makedirs(plots_dir, exist_ok=True)

def log(msg):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg.rstrip() + "\n")

ref = pd.read_csv(centroids_csv)
if 'sub_CST' not in ref.columns:
    if 'subCST' in ref.columns:
        ref = ref.rename(columns={'subCST':'sub_CST'})
    else:
        raise SystemExit("ERROR: centroids CSV must contain sub_CST column")

id_cols = {'sampleID', 'read_count', 'sub_CST', 'subCST'}
taxa_cols = [c for c in ref.columns if c not in id_cols]

def norm_name(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r'\s+', ' ', s)
    s = s.replace('_', ' ')
    return s.lower()

taxa_norm_map = {c: norm_name(c) for c in taxa_cols}

def parse_kraken_report(path: str):
    d = {}
    total_reads = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.rstrip("\n")
            if not ln.strip():
                continue
            parts = ln.split("\t")
            if len(parts) < 6:
                parts = re.split(r'\s+', ln, maxsplit=5)
                if len(parts) < 6:
                    continue
            try:
                clade_reads = int(parts[1])
            except Exception:
                continue
            rank = parts[3].strip()
            name = parts[5].strip()
            if total_reads is None:
                total_reads = clade_reads
            key = norm_name(name)
            pri = {'S':3,'G':2}.get(rank, 1)
            if key not in d:
                d[key] = (clade_reads, pri)
            else:
                if pri > d[key][1]:
                    d[key] = (clade_reads, pri)
    d2 = {k:v[0] for k,v in d.items()}
    if total_reads is None:
        total_reads = 0
    return total_reads, d2

def yue_distance(row, median):
    taxon_count = 0
    median_times_obs = []
    median_minus_obs_sq = []
    for taxon_abund in row:
        median_times_obs.append(median.iloc[taxon_count] * taxon_abund)
        median_minus_obs_sq.append((median.iloc[taxon_count] - taxon_abund) ** 2)
        taxon_count += 1
    product = np.nansum(median_times_obs)
    diff_sq = np.nansum(median_minus_obs_sq)
    return product / (diff_sq + product) if (diff_sq + product) != 0 else 0.0

CSTs = ['I-A','I-B','II','III-A','III-B','IV-A','IV-B','IV-C0','IV-C1','IV-C2','IV-C3','IV-C4','V']

n_centroids = 13
if len(ref) < n_centroids:
    raise SystemExit(f"ERROR: centroids file has {len(ref)} rows, expected >= {n_centroids}")

reference_centroids = ref.tail(n_centroids).fillna(0)
reference_centroids = reference_centroids.set_index('sub_CST')
for c in taxa_cols:
    if c not in reference_centroids.columns:
        reference_centroids[c] = 0.0
reference_centroids = reference_centroids[taxa_cols].apply(pd.to_numeric, errors="coerce").fillna(0.0)

reports = [p for p in os.listdir(kraken_dir) if p.endswith(".report.tsv")]
if not reports:
    raise SystemExit("ERROR: no kraken2 reports found to run VALENCIA")

for repfile in sorted(reports):
    unit = repfile.replace(".report.tsv", "")
    rep_path = os.path.join(kraken_dir, repfile)
    total_reads, name_to_reads = parse_kraken_report(rep_path)

    row = {'sampleID': unit, 'read_count': int(total_reads)}
    for c in taxa_cols:
        want = taxa_norm_map[c]
        reads = name_to_reads.get(want, 0)
        row[c] = int(reads)

    sample_df = pd.DataFrame([row])

    if sample_df.loc[0, 'read_count'] > 0:
        rel = sample_df[taxa_cols].div(sample_df['read_count'], axis=0)
    else:
        rel = sample_df[taxa_cols].copy()
        rel.iloc[:] = 0.0

    for cst in CSTs:
        if cst in reference_centroids.index:
            median = reference_centroids.loc[cst]
            sample_df[f"{cst}_sim"] = rel.apply(lambda x: yue_distance(x[taxa_cols], median), axis=1)
        else:
            sample_df[f"{cst}_sim"] = np.nan

    sim_cols = [f"{c}_sim" for c in CSTs]
    sample_df['subCST'] = sample_df[sim_cols].idxmax(axis=1).str.replace('_sim', '', regex=False)
    sample_df['score'] = sample_df[sim_cols].max(axis=1)

    sample_df['CST'] = sample_df['subCST'].replace({
        'I-A':'I','I-B':'I',
        'III-A':'III','III-B':'III',
        'IV-C0':'IV-C','IV-C1':'IV-C','IV-C2':'IV-C','IV-C3':'IV-C','IV-C4':'IV-C'
    })

    out_input = os.path.join(out_dir, f"{unit}_valencia_input.csv")
    out_assign = os.path.join(out_dir, f"{unit}_valencia_assignments.csv")
    sample_df[['sampleID','read_count'] + taxa_cols].to_csv(out_input, index=False)
    sample_df.to_csv(out_assign, index=False)

    try:
        rel_row = (sample_df[taxa_cols].iloc[0] / max(sample_df['read_count'].iloc[0], 1)).sort_values(ascending=False)
        top = rel_row.head(15)
        plt.figure()
        top[::-1].plot(kind='barh')
        plt.xlabel("Relative abundance (approx)")
        plt.title(f"{unit} - centroid taxa (top 15)")
        plt.tight_layout()
        plt.savefig(os.path.join(plots_dir, f"{unit}_valencia_taxa_top15.png"), dpi=180)
        plt.close()

        sim = sample_df[sim_cols].iloc[0].sort_values(ascending=False)
        plt.figure()
        sim.plot(kind='bar')
        plt.ylabel("Similarity score")
        plt.title(f"{unit} - VALENCIA similarity")
        plt.xticks(rotation=45, ha='right')
        plt.tight_layout()
        plt.savefig(os.path.join(plots_dir, f"{unit}_valencia_similarity.png"), dpi=180)
        plt.close()
    except Exception as e:
        log(f"[valencia] WARN plot failed for {unit}: {e}")

    log(f"[valencia] OK unit={unit} input={out_input} assignments={out_assign}")
PY

  ec=$?
  set -e
  ended="$(iso_now)"

  if [[ $ec -ne 0 ]]; then
    steps_append "${STEPS_JSON}" "valencia" "failed" "VALENCIA failed (kraken-report driven). See logs/valencia.log" "python3" "python3 valencia_from_kraken" "${ec}" "${started}" "${ended}"
    exit 3
  else
    steps_append "${STEPS_JSON}" "valencia" "succeeded" "VALENCIA completed (kraken-report driven) + plots" "python3" "python3 valencia_from_kraken" "0" "${started}" "${ended}"

    tmp="${OUTPUTS_JSON}.tmp"
    jq --arg valencia_dir "${VALENCIA_DIR}" \
       --arg valencia_log "${VALENCIA_LOG}" \
       --arg valencia_centroids_csv "${STAGED_VALENCIA_CENTROIDS}" \
       --arg valencia_plots_dir "${VALENCIA_DIR}/plots" \
       '. + {valencia:{dir:$valencia_dir, log:$valencia_log, centroids_csv:($valencia_centroids_csv|select(length>0)//null), plots_dir:($valencia_plots_dir|select(length>0)//null)}}' "${OUTPUTS_JSON}" > "${tmp}"
    mv "${tmp}" "${OUTPUTS_JSON}"
  fi
  fi  # end pandas check
fi

# -----------------------------
# Postprocessing: Generate summary tables and plots
# -----------------------------
POSTPROCESS_DIR="${RESULTS_DIR}/postprocess"
POSTPROCESS_LOG="${LOGS_DIR}/postprocess.log"
FINAL_DIR="${MODULE_OUT_DIR}/final"
mkdir -p "${POSTPROCESS_DIR}" "${FINAL_DIR}" "${FINAL_DIR}/plots" "${FINAL_DIR}/tables"

started="$(iso_now)"
set +e

python3 - "${KRAKEN_DIR}" "${POSTPROCESS_DIR}" "${FINAL_DIR}" "${VALENCIA_DIR}" "${POSTPROCESS_LOG}" "${SAMPLE_ID}" <<'PY'
import os
import sys
import csv
import json
from pathlib import Path
from collections import defaultdict

kraken_dir = Path(sys.argv[1])
postprocess_dir = Path(sys.argv[2])
final_dir = Path(sys.argv[3])
valencia_dir = Path(sys.argv[4])
log_path = Path(sys.argv[5])
sample_id = sys.argv[6]

def log(msg):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg.rstrip() + "\n")
    print(msg)

log("[postprocess] Starting postprocessing...")

# Parse kraken2 reports
def parse_kreport(path):
    """Parse kraken2 report and return rows by rank."""
    rows_by_rank = defaultdict(list)
    total_reads = 0

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < 6:
                continue
            try:
                pct = float(parts[0])
                clade_reads = int(parts[1])
                taxon_reads = int(parts[2])
                rank = parts[3].strip()
                taxid = parts[4].strip()
                name = parts[5].strip()

                if rank == "U":
                    continue
                if rank == "R":
                    total_reads = clade_reads
                    continue

                rows_by_rank[rank].append({
                    "taxid": taxid,
                    "name": name,
                    "clade_reads": clade_reads,
                    "taxon_reads": taxon_reads,
                    "pct": pct
                })
            except (ValueError, IndexError):
                continue

    return rows_by_rank, total_reads

# Find all kraken reports
reports = list(kraken_dir.glob("*.report.tsv"))
if not reports:
    log("[postprocess] No kraken2 reports found, skipping summarization")
    sys.exit(0)

log(f"[postprocess] Found {len(reports)} kraken2 report(s)")

# Process each report
all_species = []
all_genus = []

for report_path in reports:
    unit = report_path.stem.replace(".report", "")
    rows_by_rank, total_reads = parse_kreport(report_path)

    # Species level (S)
    for row in rows_by_rank.get("S", []):
        frac = row["clade_reads"] / total_reads if total_reads > 0 else 0
        all_species.append({
            "sample_id": unit,
            "taxid": row["taxid"],
            "species": row["name"],
            "reads": row["clade_reads"],
            "fraction": frac
        })

    # Genus level (G)
    for row in rows_by_rank.get("G", []):
        frac = row["clade_reads"] / total_reads if total_reads > 0 else 0
        all_genus.append({
            "sample_id": unit,
            "taxid": row["taxid"],
            "genus": row["name"],
            "reads": row["clade_reads"],
            "fraction": frac
        })

# Write tidy CSVs
def write_tidy_csv(path, rows, taxon_col):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["sample_id", "taxid", taxon_col, "reads", "fraction"])
        w.writeheader()
        for r in rows:
            w.writerow(r)

species_tidy = postprocess_dir / "kraken_species_tidy.csv"
genus_tidy = postprocess_dir / "kraken_genus_tidy.csv"

if all_species:
    write_tidy_csv(species_tidy, all_species, "species")
    log(f"[postprocess] Wrote species tidy CSV: {species_tidy}")

if all_genus:
    write_tidy_csv(genus_tidy, all_genus, "genus")
    log(f"[postprocess] Wrote genus tidy CSV: {genus_tidy}")

# Generate plots
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np

    def plot_stacked_bar(data, taxon_col, title, out_path, top_n=15):
        """Create stacked bar plot of top taxa."""
        if not data:
            return

        # Get samples and aggregate by taxon
        samples = sorted(set(r["sample_id"] for r in data))
        taxon_totals = defaultdict(float)
        for r in data:
            taxon_totals[r[taxon_col]] += r["fraction"]

        # Get top taxa
        top_taxa = sorted(taxon_totals.keys(), key=lambda x: taxon_totals[x], reverse=True)[:top_n]

        # Build matrix
        sample_taxon_frac = {s: defaultdict(float) for s in samples}
        for r in data:
            sample_taxon_frac[r["sample_id"]][r[taxon_col]] += r["fraction"]

        # Plot
        fig, ax = plt.subplots(figsize=(max(8, len(samples)*1.5), 8))

        x = np.arange(len(samples))
        bottom = np.zeros(len(samples))

        colors = plt.cm.tab20(np.linspace(0, 1, len(top_taxa) + 1))

        for i, taxon in enumerate(top_taxa):
            vals = np.array([sample_taxon_frac[s].get(taxon, 0) for s in samples])
            ax.bar(x, vals, bottom=bottom, label=taxon, color=colors[i], width=0.8)
            bottom += vals

        # Add "Other" category
        other_vals = []
        for s in samples:
            total = sum(sample_taxon_frac[s].values())
            top_sum = sum(sample_taxon_frac[s].get(t, 0) for t in top_taxa)
            other_vals.append(total - top_sum)
        other_vals = np.array(other_vals)
        if other_vals.sum() > 0:
            ax.bar(x, other_vals, bottom=bottom, label="Other", color=colors[-1], width=0.8)

        ax.set_xticks(x)
        ax.set_xticklabels(samples, rotation=45, ha="right")
        ax.set_ylabel("Relative Abundance")
        ax.set_title(title)
        ax.legend(bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=8)
        ax.set_ylim(0, 1.0)

        plt.tight_layout()
        plt.savefig(out_path, dpi=200, bbox_inches="tight")
        plt.close()
        log(f"[postprocess] Generated plot: {out_path}")

    def plot_pie(data, taxon_col, title, out_path, top_n=12):
        """Create pie chart of overall composition."""
        if not data:
            return

        taxon_totals = defaultdict(float)
        for r in data:
            taxon_totals[r[taxon_col]] += r["reads"]

        total = sum(taxon_totals.values())
        if total == 0:
            return

        # Get top taxa
        sorted_taxa = sorted(taxon_totals.items(), key=lambda x: x[1], reverse=True)
        top_taxa = sorted_taxa[:top_n]
        other_sum = sum(v for _, v in sorted_taxa[top_n:])

        labels = [t[0] for t in top_taxa]
        values = [t[1] for t in top_taxa]
        if other_sum > 0:
            labels.append("Other")
            values.append(other_sum)

        fig, ax = plt.subplots(figsize=(10, 10))
        colors = plt.cm.tab20(np.linspace(0, 1, len(labels)))

        wedges, texts, autotexts = ax.pie(
            values, labels=None, autopct=lambda p: f'{p:.1f}%' if p >= 2 else '',
            colors=colors, pctdistance=0.8
        )

        ax.legend(wedges, labels, loc="center left", bbox_to_anchor=(1, 0.5), fontsize=9)
        ax.set_title(title)

        plt.tight_layout()
        plt.savefig(out_path, dpi=200, bbox_inches="tight")
        plt.close()
        log(f"[postprocess] Generated plot: {out_path}")

    # Generate species plots
    if all_species:
        plot_stacked_bar(
            all_species, "species",
            "Species Relative Abundance (Top 15)",
            final_dir / "plots" / "species_stacked_bar.png"
        )
        plot_pie(
            all_species, "species",
            "Overall Species Composition",
            final_dir / "plots" / "species_pie.png"
        )

    # Generate genus plots
    if all_genus:
        plot_stacked_bar(
            all_genus, "genus",
            "Genus Relative Abundance (Top 15)",
            final_dir / "plots" / "genus_stacked_bar.png"
        )
        plot_pie(
            all_genus, "genus",
            "Overall Genus Composition",
            final_dir / "plots" / "genus_pie.png"
        )

except ImportError as e:
    log(f"[postprocess] matplotlib not available, skipping plots: {e}")
except Exception as e:
    log(f"[postprocess] Plot generation failed: {e}")

# Copy key outputs to final directory
import shutil

# Copy kraken reports
for report in reports:
    shutil.copy2(report, final_dir / "tables" / report.name)
    log(f"[postprocess] Copied {report.name} to final/tables/")

# Copy summary CSVs
if species_tidy.exists():
    shutil.copy2(species_tidy, final_dir / "tables" / "kraken_species_tidy.csv")
if genus_tidy.exists():
    shutil.copy2(genus_tidy, final_dir / "tables" / "kraken_genus_tidy.csv")

# Copy VALENCIA outputs if they exist
valencia_path = Path(valencia_dir)
if valencia_path.exists():
    valencia_final = final_dir / "valencia"
    valencia_final.mkdir(exist_ok=True)

    for f in valencia_path.glob("*_valencia_assignments.csv"):
        shutil.copy2(f, valencia_final / f.name)
        log(f"[postprocess] Copied VALENCIA assignment: {f.name}")

    valencia_plots = valencia_path / "plots"
    if valencia_plots.exists():
        valencia_plots_final = valencia_final / "plots"
        valencia_plots_final.mkdir(exist_ok=True)
        for f in valencia_plots.glob("*.png"):
            shutil.copy2(f, valencia_plots_final / f.name)
            log(f"[postprocess] Copied VALENCIA plot: {f.name}")

# Write manifest
manifest = {
    "module": "sr_meta",
    "sample_id": sample_id,
    "outputs": {
        "tables": sorted([f.name for f in (final_dir / "tables").glob("*")]),
        "plots": sorted([f.name for f in (final_dir / "plots").glob("*.png")]),
        "valencia": sorted([f.name for f in (final_dir / "valencia").glob("*")]) if (final_dir / "valencia").exists() else []
    }
}

manifest_path = final_dir / "manifest.json"
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
log(f"[postprocess] Wrote manifest: {manifest_path}")

log("[postprocess] Postprocessing complete!")
PY

POSTPROCESS_EC=$?
set -e
ended="$(iso_now)"

if [[ "${POSTPROCESS_EC}" -ne 0 ]]; then
  steps_append "${STEPS_JSON}" "postprocess" "failed" "Postprocessing failed (see logs/postprocess.log)" "python3" "python3 postprocess" "${POSTPROCESS_EC}" "${started}" "${ended}"
else
  steps_append "${STEPS_JSON}" "postprocess" "succeeded" "Postprocessing completed (tables + plots)" "python3" "python3 postprocess" "0" "${started}" "${ended}"

  tmp="${OUTPUTS_JSON}.tmp"
  jq --arg postprocess_dir "${POSTPROCESS_DIR}" \
     --arg postprocess_log "${POSTPROCESS_LOG}" \
     --arg final_dir "${FINAL_DIR}" \
     '. + {postprocess:{dir:$postprocess_dir, log:$postprocess_log}, final_dir:$final_dir}' "${OUTPUTS_JSON}" > "${tmp}"
  mv "${tmp}" "${OUTPUTS_JSON}"
fi

echo "[${MODULE_NAME}] Done"
print_step_status "${STEPS_JSON}" "fastqc"
print_step_status "${STEPS_JSON}" "multiqc"
print_step_status "${STEPS_JSON}" "cutadapt_demux"
print_step_status "${STEPS_JSON}" "fastp_trim_filter"
print_step_status "${STEPS_JSON}" "host_depletion"
print_step_status "${STEPS_JSON}" "kraken2"
print_step_status "${STEPS_JSON}" "valencia"
print_step_status "${STEPS_JSON}" "postprocess"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
echo "[${MODULE_NAME}] final outputs: ${FINAL_DIR}"
