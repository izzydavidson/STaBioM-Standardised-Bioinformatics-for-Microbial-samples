#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH=""

usage() {
  echo "Usage: $0 --config <effective_config.json>"
  exit 1
}

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
  echo "ERROR: effective config not found: ${CONFIG_PATH}" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required" >&2
  exit 3
fi

RUN_DIR="$(python3 - "$CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
  cfg = json.load(f)
print(cfg.get("run", {}).get("run_dir", ""))
PY
)"

if [[ -z "${RUN_DIR}" ]]; then
  echo "ERROR: run.run_dir missing in effective config: ${CONFIG_PATH}" >&2
  exit 2
fi

if [[ ! -d "${RUN_DIR}" ]]; then
  echo "ERROR: run_dir does not exist on disk: ${RUN_DIR}" >&2
  exit 2
fi

mkdir -p "${RUN_DIR}/logs"
LOG_PATH="${RUN_DIR}/logs/pipeline.log"
touch "${LOG_PATH}"

echo "[MODULE sr_meta] starting" >> "${LOG_PATH}"

mkdir -p "${RUN_DIR}/results/report" "${RUN_DIR}/results/tables" "${RUN_DIR}/results/plots"

echo "This is a placeholder report for sr_meta." > "${RUN_DIR}/results/report/index.html"
echo -e "metric\tvalue\nplaceholder\t1" > "${RUN_DIR}/results/tables/summary.tsv"

PIPELINE_ID="$(python3 - "$CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
  cfg = json.load(f)
print(cfg.get("pipeline_id",""))
PY
)"

RUN_ID="$(python3 - "$CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
  cfg = json.load(f)
print(cfg.get("run",{}).get("run_id",""))
PY
)"

CREATED_AT="$(python3 - <<'PY'
from datetime import datetime, timezone, timedelta
tz = timezone(timedelta(hours=10))
print(datetime.now(tz).isoformat(timespec="seconds"))
PY
)"

python3 - "$PIPELINE_ID" "$RUN_ID" "$RUN_DIR" "$CREATED_AT" > "${RUN_DIR}/outputs.json.tmp" <<'PY'
import json, sys
pipeline_id, run_id, run_dir, created_at = sys.argv[1:]
doc = {
  "pipeline_id": pipeline_id,
  "run_id": run_id,
  "run_dir": run_dir,
  "created_at": created_at,
  "outputs": [
    {"id": "pipeline_log", "label": "Pipeline log", "type": "log", "path": "logs/pipeline.log"},
    {"id": "placeholder_report", "label": "Placeholder report", "type": "html", "path": "results/report/index.html"},
    {"id": "placeholder_summary", "label": "Placeholder summary table", "type": "tsv", "path": "results/tables/summary.tsv"}
  ]
}
print(json.dumps(doc, ensure_ascii=False, indent=2))
PY

mv "${RUN_DIR}/outputs.json.tmp" "${RUN_DIR}/outputs.json"
printf "\n" >> "${RUN_DIR}/outputs.json"

echo "[MODULE sr_meta] wrote outputs.json + placeholders" >> "${LOG_PATH}"
exit 0
