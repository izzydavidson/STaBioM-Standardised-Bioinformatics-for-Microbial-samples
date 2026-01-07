#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --config <path/to/config.json>"
  exit 1
}

CONFIG_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "${CONFIG_PATH}" ]]; then
  usage
fi

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "ERROR: Config file not found: ${CONFIG_PATH}" >&2
  exit 2
fi

# Resolve paths relative to where THIS script lives (so it works no matter your cwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
CAPABILITIES_PATH="${SCRIPT_DIR}/capabilities.json"

require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required but not found on PATH" >&2
    exit 3
  fi
}

json_get() {
  local expr="$1"
  python3 - "$CONFIG_PATH" "$expr" <<'PY'
import json, sys
path = sys.argv[1]
expr = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

cur = data
for part in expr.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print("")
        sys.exit(0)

if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(str(cur))
PY
}

sanitize_id() {
  python3 - "$1" <<'PY'
import re, sys
s = sys.argv[1].strip()
s = s.replace(" ", "_")
s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
s = re.sub(r"_+", "_", s)
s = s.strip("._-")
print(s.lower() if s else "")
PY
}

now_iso() {
  python3 - <<'PY'
from datetime import datetime, timezone, timedelta
tz = timezone(timedelta(hours=10))
print(datetime.now(tz).isoformat(timespec="seconds"))
PY
}

write_json_atomic() {
  local out_path="$1"
  local json_payload="$2"
  local tmp="${out_path}.tmp"
  printf "%s\n" "${json_payload}" > "${tmp}"
  mv "${tmp}" "${out_path}"
}

status_update() {
  local run_dir="$1"
  local state="$2"
  local step="$3"
  local message="$4"
  local progress="${5:-}"
  local updated_at
  updated_at="$(now_iso)"

  local payload
  if [[ -n "${progress}" ]]; then
    payload="$(python3 - "$state" "$step" "$message" "$updated_at" "$progress" <<'PY'
import json, sys
state, step, message, updated_at, progress = sys.argv[1:]
print(json.dumps({
  "state": state,
  "step": step,
  "message": message,
  "updated_at": updated_at,
  "progress": int(progress),
}, ensure_ascii=False, indent=2))
PY
)"
  else
    payload="$(python3 - "$state" "$step" "$message" "$updated_at" <<'PY'
import json, sys
state, step, message, updated_at = sys.argv[1:]
print(json.dumps({
  "state": state,
  "step": step,
  "message": message,
  "updated_at": updated_at,
}, ensure_ascii=False, indent=2))
PY
)"
  fi

  write_json_atomic "${run_dir}/status.json" "${payload}"
}

capabilities_has_pipeline() {
  local pipeline_key="$1"
  python3 - "$CAPABILITIES_PATH" "$pipeline_key" <<'PY'
import json, sys
cap_path = sys.argv[1]
key = sys.argv[2]
with open(cap_path, "r", encoding="utf-8") as f:
  cap = json.load(f)
pipelines = cap.get("pipelines", {})
print("1" if key in pipelines else "0")
PY
}

require_python

PIPELINE_ID="$(json_get "pipeline_id")"
WORK_DIR="$(json_get "run.work_dir")"
RUN_ID="$(json_get "run.run_id")"
FORCE_OVERWRITE="$(json_get "run.force_overwrite")"

if [[ -z "${PIPELINE_ID}" ]]; then
  echo "ERROR: Missing pipeline_id in config" >&2
  exit 4
fi
if [[ -z "${WORK_DIR}" ]]; then
  echo "ERROR: Missing run.work_dir in config" >&2
  exit 4
fi
if [[ -z "${RUN_ID}" ]]; then
  echo "ERROR: Missing run.run_id in config" >&2
  exit 4
fi
if [[ -z "${FORCE_OVERWRITE}" ]]; then
  FORCE_OVERWRITE="0"
fi

PIPELINE_KEY="$(sanitize_id "${PIPELINE_ID}")"
if [[ -z "${PIPELINE_KEY}" ]]; then
  echo "ERROR: pipeline_id normalised to empty string: '${PIPELINE_ID}'" >&2
  exit 4
fi

# Step 6: validate pipeline_id exists in capabilities.json (clearer errors early)
if [[ ! -f "${CAPABILITIES_PATH}" ]]; then
  echo "ERROR: capabilities.json not found at: ${CAPABILITIES_PATH}" >&2
  echo "       Create it at pipelines/capabilities.json (relative to this dispatcher)." >&2
  exit 4
fi

HAS_PIPELINE="$(capabilities_has_pipeline "${PIPELINE_KEY}")"
if [[ "${HAS_PIPELINE}" != "1" ]]; then
  echo "ERROR: pipeline_id '${PIPELINE_ID}' (normalized: '${PIPELINE_KEY}') not found in capabilities.json" >&2
  echo "       Add it under pipelines.<id> in: ${CAPABILITIES_PATH}" >&2
  exit 5
fi

RUN_ID_RESOLVED="$(sanitize_id "${RUN_ID}")"
if [[ -z "${RUN_ID_RESOLVED}" ]]; then
  RUN_ID_RESOLVED="run_$(date +%Y%m%d_%H%M%S)"
fi

RUN_DIR="${WORK_DIR%/}/${RUN_ID_RESOLVED}"

# Map pipeline_id -> module script (still explicit for now)
case "${PIPELINE_KEY}" in
  lr_meta)
    MODULE_SCRIPT="${MODULES_DIR}/lr_meta.sh"
    ;;
  lr_amp)
    MODULE_SCRIPT="${MODULES_DIR}/lr_amp.sh"
    ;;
  sr_meta)
    MODULE_SCRIPT="${MODULES_DIR}/sr_meta.sh"
    ;;
  sr_amp)
    MODULE_SCRIPT="${MODULES_DIR}/sr_amp.sh"
    ;;
  *)
    echo "ERROR: No module mapping for pipeline_id '${PIPELINE_ID}' (normalized: '${PIPELINE_KEY}')" >&2
    echo "       Add a mapping in pipelines/stabiom_run.sh case statement." >&2
    exit 5
    ;;
esac

if [[ ! -f "${MODULE_SCRIPT}" ]]; then
  echo "ERROR: Module script not found: ${MODULE_SCRIPT}" >&2
  exit 5
fi

if [[ -d "${RUN_DIR}" ]]; then
  if [[ "${FORCE_OVERWRITE}" == "1" ]]; then
    rm -rf "${RUN_DIR}"
  else
    echo "ERROR: Run directory already exists: ${RUN_DIR}" >&2
    echo "       Set run.force_overwrite=1 to overwrite." >&2
    exit 6
  fi
fi

mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/inputs" "${RUN_DIR}/work" "${RUN_DIR}/results"

LOG_PATH="${RUN_DIR}/logs/pipeline.log"
touch "${LOG_PATH}"

EFFECTIVE_CONFIG_PATH="${RUN_DIR}/effective_config.json"

python3 - "$CONFIG_PATH" "$RUN_ID_RESOLVED" "$RUN_DIR" > "${EFFECTIVE_CONFIG_PATH}.tmp" <<'PY'
import json, sys
cfg_path, run_id_resolved, run_dir = sys.argv[1:]
with open(cfg_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

cfg.setdefault("run", {})
cfg["run"]["run_id_resolved"] = run_id_resolved
cfg["run"]["run_dir"] = run_dir

print(json.dumps(cfg, ensure_ascii=False, indent=2))
PY
mv "${EFFECTIVE_CONFIG_PATH}.tmp" "${EFFECTIVE_CONFIG_PATH}"

status_update "${RUN_DIR}" "running" "init" "Run started" 5

set +e
bash "${MODULE_SCRIPT}" --config "${EFFECTIVE_CONFIG_PATH}"
MODULE_EXIT=$?
set -e

if [[ ${MODULE_EXIT} -ne 0 ]]; then
  status_update "${RUN_DIR}" "failed" "module" "Pipeline module failed (exit ${MODULE_EXIT})"
  echo "ERROR: Module failed with exit code ${MODULE_EXIT}" >> "${LOG_PATH}"
  exit ${MODULE_EXIT}
fi

if [[ ! -f "${RUN_DIR}/outputs.json" ]]; then
  status_update "${RUN_DIR}" "failed" "outputs" "outputs.json was not created by module"
  echo "ERROR: outputs.json missing" >> "${LOG_PATH}"
  exit 7
fi

status_update "${RUN_DIR}" "succeeded" "done" "Run completed successfully" 100
echo "DONE: ${RUN_DIR}"
