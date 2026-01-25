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
if [[ ! -f "${TOOLS_SH}" ]]; then
  echo "ERROR: Missing shared tools file: ${TOOLS_SH}" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "${TOOLS_SH}"

############################################
##              COLOURS                   ##
############################################
BOLD="\033[1m"
RESET="\033[0m"
GREEN="\033[32m"
RED="\033[31m"
PURPLE="\033[35m"
CYAN="\033[36m"
YELLOW="\033[33m"

log() { echo -e "[$(date '+%F %T')] $*" >&2; }
log_info() { log "${CYAN}${BOLD}$*${RESET}"; }
log_warn() { log "${YELLOW}${BOLD}$*${RESET}"; }
log_ok() { log "${GREEN}${BOLD}$*${RESET}"; }
log_done() { log "${PURPLE}${BOLD}$*${RESET}"; }
log_fail() { log "${RED}${BOLD}$*${RESET}"; }

die() { log_fail "$*"; exit 1; }

on_error() {
  local lineno="$1"
  local cmd="$2"
  log_fail "FAILED at line ${lineno}: ${cmd}"
  log_fail "Pipeline stopped."
}
trap 'on_error ${LINENO} "${BASH_COMMAND}"' ERR

############################################
##              HELPERS                   ##
############################################

jq_first() {
  local file="$1"; shift
  local v=""
  for expr in "$@"; do
    v="$(jq -er "${expr} // empty" "${file}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then echo "${v}"; return 0; fi
  done
  return 1
}

require_file() {
  local p="$1"
  [[ -n "${p}" && "${p}" != "null" ]] || { echo "ERROR: Required file path is empty" >&2; exit 2; }
  [[ -f "${p}" ]] || { echo "ERROR: File not found: ${p}" >&2; exit 2; }
}

require_dir() {
  local p="$1"
  [[ -n "${p}" && "${p}" != "null" ]] || { echo "ERROR: Required directory path is empty" >&2; exit 2; }
  [[ -d "${p}" ]] || { echo "ERROR: Directory not found: ${p}" >&2; exit 2; }
}

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

# Resolve FASTQ input(s) to a newline-separated list of file paths.
resolve_fastq_list() {
  local config_path="$1"
  local resolved=()

  local fastq_val
  fastq_val="$(jq -r '.input.fastq // .inputs.fastq // empty' "${config_path}" 2>/dev/null || true)"

  local fastqs_val
  fastqs_val="$(jq -r '.input.fastqs // .inputs.fastqs // empty' "${config_path}" 2>/dev/null || true)"

  local is_array
  is_array="$(jq -r 'if (.input.fastq // .inputs.fastq) | type == "array" then "yes" else "no" end' "${config_path}" 2>/dev/null || echo "no")"

  if [[ "${is_array}" == "yes" ]]; then
    while IFS= read -r path; do
      [[ -n "${path}" && "${path}" != "null" ]] || continue
      resolved+=("${path}")
    done < <(jq -r '(.input.fastq // .inputs.fastq) | .[]' "${config_path}" 2>/dev/null)
  elif [[ -n "${fastq_val}" && "${fastq_val}" != "null" ]]; then
    resolved+=("${fastq_val}")
  fi

  local is_fastqs_array
  is_fastqs_array="$(jq -r 'if (.input.fastqs // .inputs.fastqs) | type == "array" then "yes" else "no" end' "${config_path}" 2>/dev/null || echo "no")"

  if [[ "${is_fastqs_array}" == "yes" ]]; then
    while IFS= read -r path; do
      [[ -n "${path}" && "${path}" != "null" ]] || continue
      resolved+=("${path}")
    done < <(jq -r '(.input.fastqs // .inputs.fastqs) | .[]' "${config_path}" 2>/dev/null)
  elif [[ -n "${fastqs_val}" && "${fastqs_val}" != "null" ]]; then
    resolved+=("${fastqs_val}")
  fi

  local final_files=()
  for entry in "${resolved[@]}"; do
    [[ -n "${entry}" ]] || continue

    if [[ -f "${entry}" ]]; then
      final_files+=("${entry}")
    elif [[ -d "${entry}" ]]; then
      while IFS= read -r f; do
        [[ -n "${f}" ]] && final_files+=("${f}")
      done < <(find "${entry}" -maxdepth 1 -type f \( -iname "*.fastq" -o -iname "*.fq" -o -iname "*.fastq.gz" -o -iname "*.fq.gz" \) | sort)
    elif [[ "${entry}" == *"*"* || "${entry}" == *"?"* || "${entry}" == *"["* ]]; then
      shopt -s nullglob
      local expanded=( ${entry} )
      shopt -u nullglob
      for f in "${expanded[@]}"; do
        [[ -f "${f}" ]] && final_files+=("${f}")
      done
    else
      final_files+=("${entry}")
    fi
  done

  printf '%s\n' "${final_files[@]}" | sort -u
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

exit_code_means_tool_missing() {
  if command -v exit_code_means_tool_missing >/dev/null 2>&1; then
    exit_code_means_tool_missing "$@"
    return $?
  fi
  local ec="${1:-0}"
  [[ "$ec" -eq 127 ]]
}

check_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
make_dir() { [[ -d "$1" ]] || { log_info "Creating: $1"; mkdir -p "$1"; }; }

############################################
##               CONFIG                   ##
############################################

INPUT_STYLE="$(jq_first "${CONFIG_PATH}" '.input.style' '.inputs.style' '.input_style' '.inputs.input_style' || true)"
[[ -n "${INPUT_STYLE}" ]] || INPUT_STYLE="FASTQ_SINGLE"

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

if [[ -n "${PIPELINE_ID:-}" && "${PIPELINE_ID}" != "${MODULE_NAME}" ]]; then
  echo "ERROR: Config pipeline_id (${PIPELINE_ID}) does not match module (${MODULE_NAME})." >&2
  exit 2
fi

# Layout: <run_dir>/lr_amp/...
MODULE_OUT_DIR="${OUTPUT_DIR}/${MODULE_NAME}"
INPUTS_DIR="${MODULE_OUT_DIR}/inputs"
RESULTS_DIR="${MODULE_OUT_DIR}/results"
LOGS_DIR="${MODULE_OUT_DIR}/logs"
STEPS_JSON="${MODULE_OUT_DIR}/steps.json"
mkdir -p "${INPUTS_DIR}" "${RESULTS_DIR}" "${LOGS_DIR}"

FASTQ_STAGE_DIR="${INPUTS_DIR}/fastq"
RAW_READS_DIR="${RESULTS_DIR}/raw_reads"
RAW_FASTQC_DIR="${RESULTS_DIR}/raw_fastqc"
RAW_MULTIQC_DIR="${RESULTS_DIR}/raw_multiqc"
QFILTER_DIR="${RESULTS_DIR}/qfiltered"
LENFILTER_DIR="${RESULTS_DIR}/lenfiltered"
TAXO_ROOT="${RESULTS_DIR}/taxonomy"
EMU_DIR="${RESULTS_DIR}/emu"
PRIMARY_TAXO_DIR="${RESULTS_DIR}/primary_taxonomy"
VALENCIA_TMP="${RESULTS_DIR}/valencia/tmp"
VALENCIA_RESULTS="${RESULTS_DIR}/valencia/results"

mkdir -p \
  "${FASTQ_STAGE_DIR}" "${RAW_READS_DIR}" "${RAW_FASTQC_DIR}" "${RAW_MULTIQC_DIR}" \
  "${QFILTER_DIR}" "${LENFILTER_DIR}" \
  "${TAXO_ROOT}" "${EMU_DIR}" "${PRIMARY_TAXO_DIR}" \
  "${VALENCIA_TMP}" "${VALENCIA_RESULTS}"

RUN_NAME_BASE="$(jq_first "${CONFIG_PATH}" '.run.run_name' '.run.name' '.run_name' '.id' '.run_id' || true)"
[[ -n "${RUN_NAME_BASE}" ]] || RUN_NAME_BASE="$(date +%Y%m%d_%H%M%S)"
RUN_NAME="${RUN_NAME_BASE}"

SAMPLE_SHEET="$(jq_first "${CONFIG_PATH}" '.inputs.sample_sheet' '.input.sample_sheet' '.sample_sheet' '.barcode_sites_tsv' || true)"

THREADS="$(jq_first "${CONFIG_PATH}" '.resources.threads' '.run.threads' '.threads' || true)"
[[ -n "${THREADS}" ]] || THREADS="8"

# LR_AMP specific config: technology and amplicon type
TECHNOLOGY="$(jq_first "${CONFIG_PATH}" '.params.technology' '.technology' '.tools.technology' || true)"
[[ -n "${TECHNOLOGY}" ]] || TECHNOLOGY="ONT"
TECHNOLOGY="$(echo "${TECHNOLOGY}" | tr '[:lower:]' '[:upper:]')"

FULL_LENGTH="$(jq_first "${CONFIG_PATH}" '.params.full_length' '.full_length' '.amplicon.full_length' || true)"
[[ -n "${FULL_LENGTH}" ]] || FULL_LENGTH="1"

# Length filter settings for amplicons
# Full-length 16S: ~1500bp (1300-1700bp range)
# Partial/unknown: conservative wide window (200-900bp by default)
LEN_MIN_FULL="$(jq_first "${CONFIG_PATH}" '.params.len_min_full' '.amplicon.len_min_full' || true)"
[[ -n "${LEN_MIN_FULL}" ]] || LEN_MIN_FULL="1300"
LEN_MAX_FULL="$(jq_first "${CONFIG_PATH}" '.params.len_max_full' '.amplicon.len_max_full' || true)"
[[ -n "${LEN_MAX_FULL}" ]] || LEN_MAX_FULL="1700"
LEN_MIN_PARTIAL="$(jq_first "${CONFIG_PATH}" '.params.len_min_partial' '.amplicon.len_min_partial' || true)"
[[ -n "${LEN_MIN_PARTIAL}" ]] || LEN_MIN_PARTIAL="200"
LEN_MAX_PARTIAL="$(jq_first "${CONFIG_PATH}" '.params.len_max_partial' '.amplicon.len_max_partial' || true)"
[[ -n "${LEN_MAX_PARTIAL}" ]] || LEN_MAX_PARTIAL="900"

# Q-filter settings
QFILTER_ENABLED="$(jq_first "${CONFIG_PATH}" '.tools.qfilter.enabled' '.qfilter.enabled' '.qfilter_enabled' || true)"
[[ -n "${QFILTER_ENABLED}" ]] || QFILTER_ENABLED="1"
QFILTER_MIN_Q="$(jq_first "${CONFIG_PATH}" '.tools.qfilter.min_q' '.qfilter.min_q' '.qfilter_min_q' || true)"
[[ -n "${QFILTER_MIN_Q}" ]] || QFILTER_MIN_Q="10"

VALENCIA_ENABLED="$(jq_first "${CONFIG_PATH}" '.tools.valencia.enabled' '.valencia.enabled' '.valencia_enabled' || true)"
[[ -n "${VALENCIA_ENABLED}" ]] || VALENCIA_ENABLED="0"
VALENCIA_ROOT="$(jq_first "${CONFIG_PATH}" '.tools.valencia.root' '.valencia.root' || true)"

POSTPROCESS_ENABLED="$(jq_first "${CONFIG_PATH}" '.postprocess.enabled' '.tools.postprocess.enabled' '.postprocess_enabled' || true)"
[[ -n "${POSTPROCESS_ENABLED}" ]] || POSTPROCESS_ENABLED="1"

# References + DB
KRAKEN2_DB="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.db' '.tools.kraken2.db_classify' '.kraken2_db' || true)"

# Emu settings
EMU_DB="$(jq_first "${CONFIG_PATH}" '.tools.emu.db' '.emu.db' '.emu_db' || true)"

# Kraken params for amplicon
KRAKEN_CONF_VAGINAL="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.vaginal.confidence' '.kraken_confidence_vaginal' || true)"
[[ -n "${KRAKEN_CONF_VAGINAL}" ]] || KRAKEN_CONF_VAGINAL="0.1"
KRAKEN_MHG_VAGINAL="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.vaginal.minimum_hit_groups' '.kraken_min_hit_groups_vaginal' || true)"
[[ -n "${KRAKEN_MHG_VAGINAL}" ]] || KRAKEN_MHG_VAGINAL="2"

KRAKEN_CONF_NONVAGINAL="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.nonvaginal.confidence' '.kraken_confidence_nonvaginal' || true)"
[[ -n "${KRAKEN_CONF_NONVAGINAL}" ]] || KRAKEN_CONF_NONVAGINAL="0.05"
KRAKEN_MHG_NONVAGINAL="$(jq_first "${CONFIG_PATH}" '.tools.kraken2.nonvaginal.minimum_hit_groups' '.kraken_min_hit_groups_nonvaginal' || true)"
[[ -n "${KRAKEN_MHG_NONVAGINAL}" ]] || KRAKEN_MHG_NONVAGINAL="2"

USE_BRACKEN="$(jq_first "${CONFIG_PATH}" '.tools.bracken.enabled' '.use_bracken' || true)"
[[ -n "${USE_BRACKEN}" ]] || USE_BRACKEN="1"
BRACKEN_READLEN="$(jq_first "${CONFIG_PATH}" '.tools.bracken.readlen' '.bracken_readlen' || true)"
[[ -n "${BRACKEN_READLEN}" ]] || BRACKEN_READLEN="1500"
BRACKEN_AVAILABLE="1"

############################################
##   INPUT RESOLUTION + STAGING           ##
############################################

STAGED_FASTQ=""
PER_BARCODE_FASTQ_ROOT=""

case "${INPUT_STYLE}" in
  FASTQ_SINGLE)
    HAS_R1="$(jq -r '.input.fastq_r1 // .inputs.fastq_r1 // empty' "${CONFIG_PATH}" 2>/dev/null || true)"
    HAS_R2="$(jq -r '.input.fastq_r2 // .inputs.fastq_r2 // empty' "${CONFIG_PATH}" 2>/dev/null || true)"
    if [[ -n "${HAS_R1}" || -n "${HAS_R2}" ]]; then
      log_warn "Long-read pipeline detected R1/R2 FASTQ config keys. These are ignored."
      log_warn "Long-read sequencing produces single-end reads only. Using .input.fastq instead."
    fi

    FASTQ_LIST_RAW="$(resolve_fastq_list "${CONFIG_PATH}")"

    FASTQ_FILES=()
    while IFS= read -r fq_path; do
      [[ -n "${fq_path}" ]] && FASTQ_FILES+=("${fq_path}")
    done <<< "${FASTQ_LIST_RAW}"

    if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
      echo "ERROR: FASTQ_SINGLE selected but could not resolve any FASTQ file(s) from config." >&2
      exit 2
    fi

    log_info "Resolved ${#FASTQ_FILES[@]} FASTQ file(s) for processing:"
    MISSING_FILES=()
    for fq in "${FASTQ_FILES[@]}"; do
      if [[ -f "${fq}" ]]; then
        log_info "  [OK] ${fq}"
      else
        log_fail "  [MISSING] ${fq}"
        MISSING_FILES+=("${fq}")
      fi
    done

    if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
      echo "ERROR: ${#MISSING_FILES[@]} FASTQ file(s) not found:" >&2
      exit 2
    fi

    log_info "Staging ${#FASTQ_FILES[@]} FASTQ(s) into per-barcode layout..."
    STAGED_FASTQS=()
    BARCODE_IDS=()

    for fq in "${FASTQ_FILES[@]}"; do
      basename_full="$(basename "${fq}")"
      barcode_id="${basename_full%.fastq.gz}"
      barcode_id="${barcode_id%.fastq}"
      barcode_id="${barcode_id%.fq.gz}"
      barcode_id="${barcode_id%.fq}"

      barcode_dir="${RAW_READS_DIR}/${RUN_NAME}/${barcode_id}"
      make_dir "${barcode_dir}"

      if [[ "${fq}" == *.gz ]]; then
        staged_path="${barcode_dir}/${barcode_id}.fastq.gz"
      else
        staged_path="${barcode_dir}/${barcode_id}.fastq"
      fi

      ln -sfn "$(realpath "${fq}")" "${staged_path}" 2>/dev/null || cp "${fq}" "${staged_path}"
      STAGED_FASTQS+=("${staged_path}")
      BARCODE_IDS+=("${barcode_id}")
    done

    PER_BARCODE_FASTQ_ROOT="${RAW_READS_DIR}/${RUN_NAME}"
    log_info "Staged ${#STAGED_FASTQS[@]} FASTQ(s) to: ${PER_BARCODE_FASTQ_ROOT}"
    STAGED_FASTQ="${STAGED_FASTQS[0]:-}"
    ;;
  *)
    echo "ERROR: Unsupported input style: ${INPUT_STYLE}. lr_amp only supports FASTQ_SINGLE." >&2
    exit 2
    ;;
esac

OUTPUTS_JSON="${MODULE_OUT_DIR}/outputs.json"

FASTQS_JSON="[]"
BARCODES_JSON="[]"
for i in "${!STAGED_FASTQS[@]}"; do
  FASTQS_JSON="$(echo "${FASTQS_JSON}" | jq --arg fq "${STAGED_FASTQS[$i]}" '. + [$fq]')"
  BARCODES_JSON="$(echo "${BARCODES_JSON}" | jq --arg bc "${BARCODE_IDS[$i]}" '. + [$bc]')"
done

jq -n \
  --arg module_name "${MODULE_NAME}" \
  --arg pipeline_id "${PIPELINE_ID:-}" \
  --arg run_id "${RUN_ID:-}" \
  --arg input_style "${INPUT_STYLE}" \
  --arg technology "${TECHNOLOGY}" \
  --argjson full_length "${FULL_LENGTH}" \
  --arg fastq "${STAGED_FASTQ}" \
  --arg per_barcode_root "${PER_BARCODE_FASTQ_ROOT}" \
  --argjson fastq_list "${FASTQS_JSON}" \
  --argjson barcode_ids "${BARCODES_JSON}" \
  '{
    "module": $module_name,
    "pipeline_id": $pipeline_id,
    "run_id": $run_id,
    "run_name": "'"${RUN_NAME}"'",
    "input_style": $input_style,
    "technology": $technology,
    "full_length": $full_length,
    "inputs": {
      "fastq": $fastq,
      "fastq_list": $fastq_list,
      "barcode_ids": $barcode_ids,
      "per_barcode_root": $per_barcode_root,
      "sample_count": ($fastq_list | length)
    }
  }' > "${OUTPUTS_JSON}"

############################################
##              METRICS                   ##
############################################
METRICS_JSON="${MODULE_OUT_DIR}/metrics.json"
TOTAL_LINES=0
TOTAL_READS=0
SAMPLE_METRICS="[]"

for i in "${!STAGED_FASTQS[@]}"; do
  staged="${STAGED_FASTQS[$i]}"
  barcode="${BARCODE_IDS[$i]}"
  if [[ -f "${staged}" ]]; then
    lines="$(count_fastq_lines "${staged}")"
    reads="$(estimate_reads_from_lines "${lines}")"
    TOTAL_LINES=$((TOTAL_LINES + lines))
    TOTAL_READS=$((TOTAL_READS + reads))
    SAMPLE_METRICS="$(echo "${SAMPLE_METRICS}" | jq \
      --arg barcode "${barcode}" \
      --arg fastq "${staged}" \
      --argjson lines "${lines}" \
      --argjson reads "${reads}" \
      '. + [{"barcode": $barcode, "fastq": $fastq, "fastq_lines": $lines, "reads_estimate": $reads}]')"
  fi
done

jq -n \
  --arg module_name "${MODULE_NAME}" \
  --argjson total_lines "${TOTAL_LINES}" \
  --argjson total_reads "${TOTAL_READS}" \
  --argjson sample_count "${#STAGED_FASTQS[@]}" \
  --argjson samples "${SAMPLE_METRICS}" \
  '{
    "module": $module_name,
    "sample_count": $sample_count,
    "total_fastq_lines": $total_lines,
    "total_reads_estimate": $total_reads,
    "samples": $samples
  }' > "${METRICS_JSON}"

tmp="${OUTPUTS_JSON}.tmp"
jq --arg metrics_path "${METRICS_JSON}" --slurpfile metrics "${METRICS_JSON}" \
  '. + {"metrics_path":$metrics_path, "metrics":$metrics[0]}' "${OUTPUTS_JSON}" > "${tmp}"
mv "${tmp}" "${OUTPUTS_JSON}"

############################################
##     TOOL RESOLUTION (config-aware)     ##
############################################

FASTQC_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.fastqc_bin' 'fastqc')"
MULTIQC_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.multiqc_bin' 'multiqc')"
NANOFILT_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.nanofilt_bin' 'NanoFilt')"
KRAKEN2_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.kraken2.bin' 'kraken2')"
BRACKEN_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.bracken.bin' 'bracken')"
EMU_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.emu.bin' 'emu')"
GIT_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.git_bin' 'git')"
RSCRIPT_BIN="$(resolve_tool "${CONFIG_PATH}" '.tools.rscript_bin' 'Rscript')"

############################################
##     BARCODE SITE MAPPING               ##
############################################
SAMPLE_TYPE_RAW="$(jq_first "${CONFIG_PATH}" '.input.sample_type' '.specimen' '.sample_type' '.inputs.sample_type' '.run.sample_type' || true)"
SAMPLE_TYPE_NORM="$(printf "%s" "${SAMPLE_TYPE_RAW:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
[[ -n "${SAMPLE_TYPE_NORM}" ]] || SAMPLE_TYPE_NORM="unknown"

declare -A SITE_BY_BARCODE
declare -A NAME_BY_BARCODE

load_barcode_site_map() {
  local sheet="${1:-}"
  SITE_BY_BARCODE=()
  NAME_BY_BARCODE=()

  if [[ "${INPUT_STYLE}" == "FASTQ_SINGLE" && -n "${SAMPLE_TYPE_NORM}" && "${SAMPLE_TYPE_NORM}" != "unknown" ]]; then
    log_info "Using input.sample_type='${SAMPLE_TYPE_RAW}' for all samples"
    for bc in "${BARCODE_IDS[@]}"; do
      SITE_BY_BARCODE["${bc}"]="${SAMPLE_TYPE_NORM}"
    done
  fi

  if [[ -z "${sheet}" || "${sheet}" == "null" ]]; then
    log_info "No sample sheet provided; using config sample_type for all barcodes."
    return 0
  fi

  if [[ ! -f "${sheet}" ]]; then
    log_warn "Sample sheet not found: ${sheet}; using config sample_type."
    return 0
  fi

  log_info "Loading barcode site map from: ${sheet}"
  while IFS=$'\t' read -r barcode site rest; do
    [[ -z "${barcode}" || "${barcode}" == "barcode" ]] && continue
    barcode="$(echo "${barcode}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    site="$(echo "${site}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    SITE_BY_BARCODE["${barcode}"]="${site}"
  done < "${sheet}"

  log_info "Loaded site mapping for ${#SITE_BY_BARCODE[@]} barcodes"
}

is_vaginal_barcode() {
  local barcode="${1:-}"
  local site="${SITE_BY_BARCODE[${barcode}]:-unknown}"
  [[ "${site}" == "vaginal" || "${site}" == "vag" || "${site}" == "v" ]]
}

get_site_for_barcode() {
  local barcode="${1:-}"
  echo "${SITE_BY_BARCODE[${barcode}]:-unknown}"
}

check_bracken_available() {
  if ! command -v "${BRACKEN_BIN}" >/dev/null 2>&1; then
    BRACKEN_AVAILABLE="0"
    USE_BRACKEN="0"
    log_warn "Bracken not found. Bracken will be skipped."
    return 0
  fi

  [[ -n "${KRAKEN2_DB}" && "${KRAKEN2_DB}" != "null" ]] || { BRACKEN_AVAILABLE="0"; USE_BRACKEN="0"; log_warn "KRAKEN2_DB not set; bracken disabled."; return 0; }
  local kmer_file="${KRAKEN2_DB}/database${BRACKEN_READLEN}mers.kmer_distrib"
  if [[ ! -s "${kmer_file}" ]]; then
    BRACKEN_AVAILABLE="0"
    USE_BRACKEN="0"
    log_warn "Bracken kmer distribution not found at ${kmer_file}; bracken disabled."
  fi
}

############################################
##   FASTQC + MULTIQC (RAW FASTQ INPUT)   ##
############################################

qc_raw_per_barcode_fastq() {
  if ! command -v "${FASTQC_BIN}" >/dev/null 2>&1; then
    log_warn "FastQC not found - skipping QC step"
    return 0
  fi

  make_dir "${RAW_FASTQC_DIR}"
  make_dir "${RAW_MULTIQC_DIR}"

  shopt -s nullglob
  local files=( "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq.gz "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq.gz )
  [[ ${#files[@]} -gt 0 ]] || { log_warn "No per-barcode FASTQ files found for QC"; return 0; }

  for fq in "${files[@]}"; do
    log "FastQC on ${fq}"
    "${FASTQC_BIN}" -t "${THREADS}" -o "${RAW_FASTQC_DIR}" "${fq}" || log_warn "FastQC failed for ${fq}"
  done

  if command -v "${MULTIQC_BIN}" >/dev/null 2>&1; then
    "${MULTIQC_BIN}" "${RAW_FASTQC_DIR}" -o "${RAW_MULTIQC_DIR}" || log_warn "MultiQC failed"
  fi
}

############################################
##   Q-FILTER (NanoFilt, MEAN Q >= X)     ##
############################################

qfilter_mean_q_per_barcode() {
  [[ "${QFILTER_ENABLED}" == "1" ]] || { log_warn "Skipping Q-filter (qfilter.enabled=0)"; return 0; }

  if ! command -v "${NANOFILT_BIN}" >/dev/null 2>&1; then
    log_warn "Skipping Q-filter (NanoFilt not found)"
    return 0
  fi

  local out_root="${QFILTER_DIR}/${RUN_NAME_BASE}"
  make_dir "${out_root}"

  shopt -s nullglob
  local files=( "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq.gz "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq.gz )
  [[ ${#files[@]} -gt 0 ]] || { log_warn "No FASTQ files found for Q-filter"; return 0; }

  for fq in "${files[@]}"; do
    local barcode
    barcode="$(basename "$(dirname "${fq}")")"

    make_dir "${out_root}/${barcode}"
    local out_fq="${out_root}/${barcode}/${barcode}.q${QFILTER_MIN_Q}.fastq.gz"

    log "Q-filter: ${fq} -> ${out_fq}"
    if [[ "${fq}" == *.gz ]]; then
      gzip -cd "${fq}" | "${NANOFILT_BIN}" -q "${QFILTER_MIN_Q}" | gzip -c > "${out_fq}"
    else
      "${NANOFILT_BIN}" -q "${QFILTER_MIN_Q}" < "${fq}" | gzip -c > "${out_fq}"
    fi
  done

  PER_BARCODE_FASTQ_ROOT="${out_root}"
}

############################################
##   LENGTH FILTER (AMPLICON-SPECIFIC)    ##
############################################

length_filter_per_barcode() {
  local min_len max_len
  if [[ "${FULL_LENGTH}" == "1" ]]; then
    min_len="${LEN_MIN_FULL}"
    max_len="${LEN_MAX_FULL}"
    log_info "Applying full-length 16S length filter: ${min_len}-${max_len}bp"
  else
    min_len="${LEN_MIN_PARTIAL}"
    max_len="${LEN_MAX_PARTIAL}"
    log_info "Applying partial amplicon length filter: ${min_len}-${max_len}bp"
  fi

  if ! command -v "${NANOFILT_BIN}" >/dev/null 2>&1; then
    log_warn "Skipping length filter (NanoFilt not found)"
    return 0
  fi

  local out_root="${LENFILTER_DIR}/${RUN_NAME_BASE}"
  make_dir "${out_root}"

  shopt -s nullglob
  local files=( "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq.gz "${PER_BARCODE_FASTQ_ROOT}"/*/*.fastq "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq.gz "${PER_BARCODE_FASTQ_ROOT}"/*/*.fq )
  [[ ${#files[@]} -gt 0 ]] || { log_warn "No FASTQ files found for length filter"; return 0; }

  for fq in "${files[@]}"; do
    local barcode
    barcode="$(basename "$(dirname "${fq}")")"

    make_dir "${out_root}/${barcode}"
    local out_fq="${out_root}/${barcode}/${barcode}.len${min_len}-${max_len}.fastq.gz"

    log "Length filter: ${fq} -> ${out_fq}"
    if [[ "${fq}" == *.gz ]]; then
      gzip -cd "${fq}" | "${NANOFILT_BIN}" -l "${min_len}" --maxlength "${max_len}" | gzip -c > "${out_fq}"
    else
      "${NANOFILT_BIN}" -l "${min_len}" --maxlength "${max_len}" < "${fq}" | gzip -c > "${out_fq}"
    fi
  done

  PER_BARCODE_FASTQ_ROOT="${out_root}"
}

############################################
##  PRIMARY CLASSIFICATION (EMU/ASV)      ##
############################################

emu_classification_per_barcode() {
  if [[ "${FULL_LENGTH}" != "1" ]]; then
    log_info "Skipping Emu (not full-length amplicons)"
    return 0
  fi

  if ! command -v "${EMU_BIN}" >/dev/null 2>&1; then
    log_warn "Emu not found - skipping Emu classification"
    return 0
  fi

  if [[ -z "${EMU_DB}" || "${EMU_DB}" == "null" ]]; then
    log_warn "EMU_DB not set - skipping Emu classification"
    return 0
  fi

  local emu_run_dir="${EMU_DIR}/${RUN_NAME}"
  make_dir "${emu_run_dir}"

  local input_dir="${PER_BARCODE_FASTQ_ROOT}"

  shopt -s nullglob
  local fqs=( "${input_dir}"/*/*.fastq.gz "${input_dir}"/*/*.fastq "${input_dir}"/*/*.fq.gz "${input_dir}"/*/*.fq )
  [[ ${#fqs[@]} -gt 0 ]] || { log_warn "No FASTQ files found for Emu classification"; return 0; }

  for fq in "${fqs[@]}"; do
    local barcode
    barcode="$(basename "$(dirname "${fq}")")"

    local out_dir="${emu_run_dir}/${barcode}"
    make_dir "${out_dir}"

    log "Emu classification: ${fq}"
    "${EMU_BIN}" abundance \
      --db "${EMU_DB}" \
      --threads "${THREADS}" \
      --output-dir "${out_dir}" \
      "${fq}" || log_warn "Emu failed for ${barcode}"
  done

  log_info "Emu classification complete: ${emu_run_dir}"
}

############################################
##  KRAKEN2 SECONDARY CLASSIFICATION      ##
############################################

kraken2_secondary_per_barcode() {
  if [[ -z "${KRAKEN2_DB}" || "${KRAKEN2_DB}" == "null" ]]; then
    log_warn "KRAKEN2_DB not set - skipping Kraken2 classification"
    return 0
  fi

  if [[ ! -d "${KRAKEN2_DB}" ]]; then
    log_warn "KRAKEN2_DB directory not found: ${KRAKEN2_DB} - skipping"
    return 0
  fi

  if ! command -v "${KRAKEN2_BIN}" >/dev/null 2>&1; then
    log_warn "Kraken2 not found - skipping taxonomy step"
    return 0
  fi

  check_bracken_available

  local input_dir="${PER_BARCODE_FASTQ_ROOT}"
  make_dir "${TAXO_ROOT}/${RUN_NAME}"

  shopt -s nullglob
  local fqs=( "${input_dir}"/*/*.fastq.gz "${input_dir}"/*/*.fastq "${input_dir}"/*/*.fq.gz "${input_dir}"/*/*.fq )
  [[ ${#fqs[@]} -gt 0 ]] || { log_warn "No FASTQ files found for Kraken2"; return 0; }

  for fq in "${fqs[@]}"; do
    local sample_id
    sample_id="$(basename "$(dirname "${fq}")")"

    make_dir "${TAXO_ROOT}/${RUN_NAME}/${sample_id}"
    local bout="${TAXO_ROOT}/${RUN_NAME}/${sample_id}"

    local conf mhg do_bracken
    do_bracken=0

    if is_vaginal_barcode "${sample_id}"; then
      conf="${KRAKEN_CONF_VAGINAL}"
      mhg="${KRAKEN_MHG_VAGINAL}"
      log_info "Sample ${sample_id} flagged as vaginal."
      if [[ "${BRACKEN_AVAILABLE}" -eq 1 && "${USE_BRACKEN}" -eq 1 ]]; then
        do_bracken=1
      fi
    else
      conf="${KRAKEN_CONF_NONVAGINAL}"
      mhg="${KRAKEN_MHG_NONVAGINAL}"
      log_info "Sample ${sample_id} treated as non-vaginal ($(get_site_for_barcode "${sample_id}"))."
      if [[ "${BRACKEN_AVAILABLE}" -eq 1 && "${USE_BRACKEN}" -eq 1 ]]; then
        do_bracken=1
      fi
    fi

    log "Kraken2 (${sample_id}) --confidence ${conf}, --minimum-hit-groups ${mhg}"
    "${KRAKEN2_BIN}" \
      --db "${KRAKEN2_DB}" \
      --threads "${THREADS}" \
      --memory-mapping \
      --use-names \
      --confidence "${conf}" \
      --minimum-hit-groups "${mhg}" \
      --report "${bout}/${sample_id}.kreport" \
      --output "${bout}/${sample_id}.kraken2" \
      "${fq}"

    if [[ "${do_bracken}" -eq 1 ]]; then
      log "Bracken (${sample_id}), readlen=${BRACKEN_READLEN}"
      "${BRACKEN_BIN}" \
        -d "${KRAKEN2_DB}" \
        -i "${bout}/${sample_id}.kreport" \
        -o "${bout}/${sample_id}.bracken" \
        -w "${bout}/${sample_id}.breport" \
        -r "${BRACKEN_READLEN}" \
        -l S || log_warn "Bracken failed for ${sample_id}"
    fi
  done
}

############################################
##       VALENCIA (vaginal only)          ##
############################################

valencia_from_taxonomy() {
  [[ "${VALENCIA_ENABLED}" -eq 1 ]] || { log_warn "Skipping VALENCIA (valencia_enabled=0)"; return 0; }
  [[ -n "${VALENCIA_ROOT}" && "${VALENCIA_ROOT}" != "null" ]] || { log_warn "Skipping VALENCIA (valencia.root not set)"; return 0; }

  make_dir "${VALENCIA_TMP}"
  make_dir "${VALENCIA_RESULTS}"
  make_dir "${VALENCIA_ROOT}"

  local val_repo="${VALENCIA_ROOT}/VALENCIA"
  if [[ ! -d "${val_repo}" ]]; then
    if [[ -n "${GIT_BIN}" ]] && command -v "${GIT_BIN}" >/dev/null 2>&1; then
      log_info "Cloning VALENCIA repo into ${val_repo}"
      "${GIT_BIN}" clone https://github.com/ravel-lab/VALENCIA.git "${val_repo}" || { log_warn "VALENCIA clone failed; skipping"; return 0; }
    else
      log_warn "git not found and VALENCIA repo missing; skipping VALENCIA"
      return 0
    fi
  fi

  local REF="${val_repo}/CST_centroids_012920.csv"
  local VALENCIA_PY="${val_repo}/Valencia.py"
  [[ -s "${REF}" ]] || { log_warn "VALENCIA centroid CSV missing; skipping"; return 0; }
  [[ -s "${VALENCIA_PY}" ]] || { log_warn "Valencia.py missing; skipping"; return 0; }

  local VALENCIA_COMBINED="${VALENCIA_TMP}/${RUN_NAME}_valencia_input.csv"
  local REP_HELPER="${VALENCIA_TMP}/report_to_valencia_ref.py"

  cat > "${REP_HELPER}" << 'PYCODE'
#!/usr/bin/env python3
import csv, sys, re, os

def norm(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace(" ", "_")
    s = re.sub(r"[^a-z0-9_]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s

def read_ref_taxa(ref_path: str):
    with open(ref_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if not header:
            raise RuntimeError("Reference centroid file has no header")
    if len(header) >= 2 and header[0].strip().lower() == "sampleid" and header[1].strip().lower() == "read_count":
        taxa = header[2:]
    else:
        taxa = header[1:]
    taxa_norm_map = {norm(t): t for t in taxa}
    return taxa, taxa_norm_map

def parse_breport(path: str):
    abund = {}
    with open(path, "r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if not row:
                continue
            name = (row[0] or "").strip()
            if not name:
                continue
            try:
                frac = float(row[-1])
            except Exception:
                continue
            if frac < 0:
                continue
            abund[name] = abund.get(name, 0.0) + frac
    return abund

def parse_kreport(path: str):
    abund = {}
    with open(path, "r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 6:
                continue
            rank = (row[3] or "").strip()
            if rank != "S":
                continue
            name = (row[5] or "").strip()
            if not name:
                continue
            try:
                pct = float((row[0] or "0").strip())
            except Exception:
                pct = 0.0
            if pct < 0:
                continue
            abund[name] = abund.get(name, 0.0) + (pct / 100.0)
    return abund

def build_row(sample_id: str, abund_raw: dict, taxa: list, taxa_norm_map: dict, read_count: int = 1):
    matched = {t: 0.0 for t in taxa}
    obs_norm = {}
    for n, v in abund_raw.items():
        key = norm(n)
        if not key:
            continue
        obs_norm[key] = obs_norm.get(key, 0.0) + float(v)
    for key_norm, canonical in taxa_norm_map.items():
        if key_norm in obs_norm:
            matched[canonical] = obs_norm[key_norm]
    total = sum(matched.values())
    if total > 0:
        for k in matched:
            matched[k] = matched[k] / total
    row = {"sampleID": sample_id, "read_count": int(read_count)}
    row.update(matched)
    return row

def main():
    if len(sys.argv) != 6:
        sys.stderr.write("Usage: report_to_valencia_ref.py MODE(breport|kreport) IN.report SAMPLE_ID REF.csv OUT.csv\n")
        sys.exit(1)
    mode, in_path, sample_id, ref_path, out_path = sys.argv[1:]
    if not os.path.exists(in_path):
        sys.stderr.write(f"Input not found: {in_path}\n")
        sys.exit(2)
    taxa, taxa_norm_map = read_ref_taxa(ref_path)
    if mode == "breport":
        abund_raw = parse_breport(in_path)
    elif mode == "kreport":
        abund_raw = parse_kreport(in_path)
    else:
        sys.stderr.write("MODE must be 'breport' or 'kreport'\n")
        sys.exit(3)
    row = build_row(sample_id, abund_raw, taxa, taxa_norm_map, read_count=1)
    fieldnames = ["sampleID", "read_count"] + taxa
    with open(out_path, "w", newline="") as out_f:
        w = csv.DictWriter(out_f, fieldnames=fieldnames)
        w.writeheader()
        w.writerow(row)

if __name__ == "__main__":
    main()
PYCODE
  chmod +x "${REP_HELPER}"

  : > "${VALENCIA_COMBINED}"
  local header_written=0
  local any_rows=0

  shopt -s nullglob

  local breps=( "${TAXO_ROOT}/${RUN_NAME}"/*/*.breport )
  for brep in "${breps[@]}"; do
    local sample_id
    sample_id="$(basename "$(dirname "${brep}")")"
    is_vaginal_barcode "${sample_id}" || continue

    local one_row_csv="${VALENCIA_TMP}/${sample_id}.${RUN_NAME}.valencia.ref.csv"
    log "VALENCIA prep (Bracken): ${brep} -> ${one_row_csv}"

    python3 "${REP_HELPER}" "breport" "${brep}" "${sample_id}" "${REF}" "${one_row_csv}" || continue

    if [[ "${header_written}" -eq 0 ]]; then
      cat "${one_row_csv}" >> "${VALENCIA_COMBINED}"
      header_written=1
    else
      tail -n +2 "${one_row_csv}" >> "${VALENCIA_COMBINED}"
    fi
    any_rows=1
  done

  if [[ "${any_rows}" -eq 0 ]]; then
    local kreps=( "${TAXO_ROOT}/${RUN_NAME}"/*/*.kreport )
    for krep in "${kreps[@]}"; do
      local sample_id
      sample_id="$(basename "$(dirname "${krep}")")"
      is_vaginal_barcode "${sample_id}" || continue

      local one_row_csv="${VALENCIA_TMP}/${sample_id}.${RUN_NAME}.valencia.ref.csv"
      log "VALENCIA prep (Kraken fallback): ${krep} -> ${one_row_csv}"

      python3 "${REP_HELPER}" "kreport" "${krep}" "${sample_id}" "${REF}" "${one_row_csv}" || continue

      if [[ "${header_written}" -eq 0 ]]; then
        cat "${one_row_csv}" >> "${VALENCIA_COMBINED}"
        header_written=1
      else
        tail -n +2 "${one_row_csv}" >> "${VALENCIA_COMBINED}"
      fi
      any_rows=1
    done
  fi

  if [[ "${any_rows}" -eq 0 ]]; then
    log_warn "No vaginal .breport or .kreport inputs found — skipping VALENCIA"
    return 0
  fi

  cp "${VALENCIA_COMBINED}" "${VALENCIA_RESULTS}/${RUN_NAME}_valencia_input.csv" || return 0

  log_info "Running VALENCIA on: ${VALENCIA_COMBINED}"

  local out_prefix="${VALENCIA_RESULTS}/${RUN_NAME}_valencia_out"
  local plot_prefix="${VALENCIA_RESULTS}/${RUN_NAME}_valencia_plot"
  local debug_log="${VALENCIA_RESULTS}/${RUN_NAME}_valencia_debug.log"

  python3 "${VALENCIA_PY}" \
    -ref "${REF}" \
    -i "${VALENCIA_COMBINED}" \
    -o "${out_prefix}" \
    -p "${plot_prefix}" \
    >"${debug_log}" 2>&1 || { log_warn "VALENCIA failed. See: ${debug_log}"; return 0; }

  log_info "VALENCIA outputs written to: ${VALENCIA_RESULTS}"
}

############################################
##         POSTPROCESS (embedded)         ##
############################################

run_postprocess() {
  [[ "${POSTPROCESS_ENABLED}" == "1" ]] || { log_warn "Skipping postprocess (postprocess.enabled=0)"; return 0; }

  local taxo_run_dir="${TAXO_ROOT}/${RUN_NAME}"
  if [[ ! -d "${taxo_run_dir}" ]]; then
    log_warn "Skipping postprocess - no taxonomy results found at ${taxo_run_dir}"
    return 0
  fi

  local postprocess_dir="${RESULTS_DIR}/postprocess"
  local postprocess_log="${LOGS_DIR}/postprocess.log"
  local final_dir="${MODULE_OUT_DIR}/final"
  mkdir -p "${postprocess_dir}" "${final_dir}" "${final_dir}/plots" "${final_dir}/tables" "${final_dir}/valencia"

  python3 - "${taxo_run_dir}" "${postprocess_dir}" "${final_dir}" "${VALENCIA_RESULTS}" "${EMU_DIR}/${RUN_NAME}" "${postprocess_log}" "${RUN_NAME}" "${MODULE_NAME}" <<'PY'
import os
import sys
import csv
import json
import shutil
from pathlib import Path
from collections import defaultdict

taxo_run_dir = Path(sys.argv[1])
postprocess_dir = Path(sys.argv[2])
final_dir = Path(sys.argv[3])
valencia_dir = Path(sys.argv[4])
emu_dir = Path(sys.argv[5])
log_path = Path(sys.argv[6])
run_name = sys.argv[7]
module_name = sys.argv[8]

def log(msg):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg.rstrip() + "\n")
    print(msg)

log(f"[postprocess] Starting postprocessing for {module_name} run: {run_name}")

def parse_kreport(path):
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
                    "taxid": taxid, "name": name,
                    "clade_reads": clade_reads, "taxon_reads": taxon_reads, "pct": pct
                })
            except (ValueError, IndexError):
                continue
    return rows_by_rank, total_reads

reports = list(taxo_run_dir.glob("*/*.kreport"))
if not reports:
    log("[postprocess] No kraken2 reports found, skipping summarization")
    sys.exit(0)

log(f"[postprocess] Found {len(reports)} kraken2 report(s)")

all_species = []
all_genus = []

for report_path in reports:
    barcode = report_path.parent.name
    rows_by_rank, total_reads = parse_kreport(report_path)
    for row in rows_by_rank.get("S", []):
        frac = row["clade_reads"] / total_reads if total_reads > 0 else 0
        all_species.append({
            "sample_id": barcode, "taxid": row["taxid"], "species": row["name"],
            "reads": row["clade_reads"], "fraction": frac
        })
    for row in rows_by_rank.get("G", []):
        frac = row["clade_reads"] / total_reads if total_reads > 0 else 0
        all_genus.append({
            "sample_id": barcode, "taxid": row["taxid"], "genus": row["name"],
            "reads": row["clade_reads"], "fraction": frac
        })

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

log("[postprocess] Tidy CSVs ready for HOST-side R postprocessing")

tables_dir = final_dir / "tables"
for report in reports:
    dest_name = f"{report.parent.name}_{report.name}"
    shutil.copy2(report, tables_dir / dest_name)
    log(f"[postprocess] Copied {dest_name} to final/tables/")

if species_tidy.exists():
    shutil.copy2(species_tidy, tables_dir / "kraken_species_tidy.csv")
if genus_tidy.exists():
    shutil.copy2(genus_tidy, tables_dir / "kraken_genus_tidy.csv")

if emu_dir.exists():
    for bc_dir in emu_dir.iterdir():
        if bc_dir.is_dir():
            for f in bc_dir.glob("*_rel-abundance*.tsv"):
                shutil.copy2(f, tables_dir / f"{bc_dir.name}_{f.name}")
                log(f"[postprocess] Copied Emu: {bc_dir.name}_{f.name}")

valencia_final = final_dir / "valencia"
if valencia_dir.exists() and any(valencia_dir.glob("*")):
    for f in valencia_dir.glob("*_valencia*.csv"):
        shutil.copy2(f, valencia_final / f.name)
        log(f"[postprocess] Copied VALENCIA: {f.name}")
    for f in valencia_dir.glob("*.png"):
        shutil.copy2(f, valencia_final / f.name)
        log(f"[postprocess] Copied VALENCIA plot: {f.name}")

plots_dir = final_dir / "plots"
manifest = {
    "module": module_name,
    "run_name": run_name,
    "outputs": {
        "tables": sorted([f.name for f in tables_dir.glob("*")]) if tables_dir.exists() else [],
        "plots": sorted([f.name for f in plots_dir.glob("*.png")]) if plots_dir.exists() else [],
        "valencia": sorted([f.name for f in valencia_final.glob("*")]) if valencia_final.exists() else []
    }
}

manifest_path = final_dir / "manifest.json"
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
log(f"[postprocess] Wrote manifest: {manifest_path}")

log("[postprocess] Postprocessing complete!")
PY
}

############################################
##                 MAIN                   ##
############################################

main() {
  load_barcode_site_map "${SAMPLE_SHEET}"

  log_info "=== lr_amp Pipeline ==="
  log_info "Technology: ${TECHNOLOGY}"
  log_info "Full-length: ${FULL_LENGTH}"
  log_info "Samples: ${#BARCODE_IDS[@]}"

  local started ended ec

  started="$(iso_now)"
  set +e
  qc_raw_per_barcode_fastq
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "raw_fastqc_multiqc" "succeeded" "raw fastqc + multiqc completed" "${FASTQC_BIN}" "fastqc + multiqc" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "raw_fastqc_multiqc" "skipped" "raw fastqc + multiqc skipped" "${FASTQC_BIN}" "fastqc + multiqc" "${ec}" "${started}" "${ended}"
  fi

  started="$(iso_now)"
  set +e
  qfilter_mean_q_per_barcode
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "qfilter" "succeeded" "qfilter completed or skipped" "${NANOFILT_BIN}" "NanoFilt" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "qfilter" "failed" "qfilter failed" "${NANOFILT_BIN}" "NanoFilt" "${ec}" "${started}" "${ended}"
    exit $ec
  fi

  started="$(iso_now)"
  set +e
  length_filter_per_barcode
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "length_filter" "succeeded" "length filter completed or skipped" "${NANOFILT_BIN}" "NanoFilt length" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "length_filter" "failed" "length filter failed" "${NANOFILT_BIN}" "NanoFilt length" "${ec}" "${started}" "${ended}"
    exit $ec
  fi

  started="$(iso_now)"
  set +e
  emu_classification_per_barcode
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "emu_primary" "succeeded" "Emu classification completed or skipped" "${EMU_BIN}" "emu abundance" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "emu_primary" "skipped" "Emu classification skipped" "${EMU_BIN}" "emu abundance" "${ec}" "${started}" "${ended}"
  fi

  started="$(iso_now)"
  set +e
  kraken2_secondary_per_barcode
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "taxonomy" "succeeded" "kraken2 (+ bracken) completed" "${KRAKEN2_BIN}" "kraken2" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "taxonomy" "failed" "taxonomy failed" "${KRAKEN2_BIN}" "kraken2" "${ec}" "${started}" "${ended}"
    exit $ec
  fi

  started="$(iso_now)"
  set +e
  valencia_from_taxonomy
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "valencia" "succeeded" "valencia completed or skipped" "python3" "Valencia.py" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "valencia" "failed" "valencia failed" "python3" "Valencia.py" "${ec}" "${started}" "${ended}"
  fi

  local postprocess_dir="${RESULTS_DIR}/postprocess"
  local postprocess_log="${LOGS_DIR}/postprocess.log"
  local final_dir="${MODULE_OUT_DIR}/final"

  started="$(iso_now)"
  set +e
  run_postprocess
  ec=$?
  set -e
  ended="$(iso_now)"
  if [[ $ec -eq 0 ]]; then
    steps_append "${STEPS_JSON}" "postprocess" "succeeded" "postprocess completed" "python3" "python3 postprocess" "${ec}" "${started}" "${ended}"
  else
    steps_append "${STEPS_JSON}" "postprocess" "failed" "postprocess failed" "python3" "python3 postprocess" "${ec}" "${started}" "${ended}"
  fi

  local taxo_run_dir="${TAXO_ROOT}/${RUN_NAME}"
  local kraken2_reports_json="[]"
  if [[ -d "${taxo_run_dir}" ]]; then
    shopt -s nullglob
    local kreport_files=( "${taxo_run_dir}"/*/*.kreport )
    shopt -u nullglob
    if [[ ${#kreport_files[@]} -gt 0 ]]; then
      kraken2_reports_json="$(printf '%s\n' "${kreport_files[@]}" | jq -R . | jq -s .)"
    fi
  fi

  tmp="${OUTPUTS_JSON}.tmp"
  jq --arg steps_path "${STEPS_JSON}" \
     --arg results_dir "${RESULTS_DIR}" \
     --arg taxo_root "${TAXO_ROOT}" \
     --arg taxo_run_dir "${taxo_run_dir}" \
     --arg emu_dir "${EMU_DIR}/${RUN_NAME}" \
     --arg valencia_results "${VALENCIA_RESULTS}" \
     --arg postprocess_dir "${postprocess_dir}" \
     --arg postprocess_log "${postprocess_log}" \
     --arg final_dir "${final_dir}" \
     --argjson kraken2_reports "${kraken2_reports_json}" \
     '. + {
        "steps_path":$steps_path,
        "results_dir":$results_dir,
        "taxonomy_root":$taxo_root,
        "taxonomy_run_dir":$taxo_run_dir,
        "emu_dir":$emu_dir,
        "kraken2": {
          "reports": $kraken2_reports,
          "results_dir": $taxo_run_dir
        },
        "valencia_results":$valencia_results,
        "postprocess":{"dir":$postprocess_dir, "log":$postprocess_log},
        "final_dir":$final_dir
      }' "${OUTPUTS_JSON}" > "${tmp}"
  mv "${tmp}" "${OUTPUTS_JSON}"

  log_done "PIPELINE COMPLETE"
  log_done "Run: ${RUN_NAME}"
  log_done "Module out: ${MODULE_OUT_DIR}"
  log_done "Outputs: ${OUTPUTS_JSON}"
}

main "$@"

echo "[${MODULE_NAME}] Step staging complete"
print_step_status "${STEPS_JSON}" "raw_fastqc_multiqc"
print_step_status "${STEPS_JSON}" "qfilter"
print_step_status "${STEPS_JSON}" "length_filter"
print_step_status "${STEPS_JSON}" "emu_primary"
print_step_status "${STEPS_JSON}" "taxonomy"
print_step_status "${STEPS_JSON}" "valencia"
print_step_status "${STEPS_JSON}" "postprocess"
echo "[${MODULE_NAME}] outputs.json: ${OUTPUTS_JSON}"
echo "[${MODULE_NAME}] final outputs: ${MODULE_OUT_DIR}/final"
