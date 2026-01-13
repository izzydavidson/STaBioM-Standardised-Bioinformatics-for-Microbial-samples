#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  pipelines/run_in_container.sh --config <path/to/config.json> [--rebuild]

What it does:
  - Reads pipeline_id from the config
  - Picks Dockerfile + image name based on pipeline_id
      lr_meta/lr_amp -> dockerfile.lr -> stabiom-tools-lr:dev
      sr_meta/sr_amp -> dockerfile.sr -> stabiom-tools-sr:dev
  - Builds the image if missing (or if --rebuild)
  - Runs pipelines/stabiom_run.sh --config <config> inside that container
  - For sr_* pipelines, mounts the host docker socket so sr_amp can docker-run qiime2 later

Optional DB mounts (recommended for Kraken2):
  - host.mounts.kraken2_db_host        -> mounted to tools.kraken2.db_host (default: /db/host)
  - host.mounts.kraken2_db_classify    -> mounted to tools.kraken2.db_classify (default: /db/classify)

These mounts are read-only (:ro).
EOF
  exit 1
}

CONFIG_PATH=""
REBUILD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --rebuild)
      REBUILD="1"
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      ;;
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

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required but not found on PATH" >&2
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found on PATH" >&2
  exit 3
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINES_DIR="${REPO_ROOT}/pipelines"
CONTAINER_DIR="${PIPELINES_DIR}/container"
DISPATCHER="${PIPELINES_DIR}/stabiom_run.sh"

if [[ ! -f "${DISPATCHER}" ]]; then
  echo "ERROR: Dispatcher not found at: ${DISPATCHER}" >&2
  exit 2
fi

CONFIG_ABS="$(cd "$(dirname "${CONFIG_PATH}")" && pwd)/$(basename "${CONFIG_PATH}")"

jq_first() {
  local file="$1"; shift
  local v=""
  for expr in "$@"; do
    v="$(jq -er "${expr} // empty" "${file}" 2>/dev/null || true)"
    if [[ -n "${v}" && "${v}" != "null" ]]; then
      printf "%s" "${v}"
      return 0
    fi
  done
  return 1
}

PIPELINE_ID_RAW="$(jq_first "${CONFIG_ABS}" \
  '.pipeline_id' \
  '.pipelineId' \
  '.pipeline.id' \
  '.pipeline.pipeline_id' \
  || true
)"

if [[ -z "${PIPELINE_ID_RAW}" || "${PIPELINE_ID_RAW}" == "null" ]]; then
  echo "ERROR: Could not find pipeline_id in config. Expected one of:" >&2
  echo "  .pipeline_id | .pipelineId | .pipeline.id | .pipeline.pipeline_id" >&2
  exit 4
fi

PIPELINE_KEY="$(echo "${PIPELINE_ID_RAW}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-' )"
PIPELINE_KEY="${PIPELINE_KEY//-/_}"

DOCKERFILE_LR="${CONTAINER_DIR}/dockerfile.lr"
DOCKERFILE_SR="${CONTAINER_DIR}/dockerfile.sr"

IMAGE_NAME=""
DOCKERFILE_PATH=""
NEEDS_DOCKER_SOCK="0"

case "${PIPELINE_KEY}" in
  lr_meta|lr_amp)
    DOCKERFILE_PATH="${DOCKERFILE_LR}"
    IMAGE_NAME="stabiom-tools-lr:dev"
    NEEDS_DOCKER_SOCK="0"
    ;;
  sr_meta|sr_amp)
    DOCKERFILE_PATH="${DOCKERFILE_SR}"
    IMAGE_NAME="stabiom-tools-sr:dev"
    NEEDS_DOCKER_SOCK="1"
    ;;
  *)
    echo "ERROR: Unknown/unsupported pipeline_id '${PIPELINE_ID_RAW}' (normalized: '${PIPELINE_KEY}')" >&2
    echo "Supported: lr_meta, lr_amp, sr_meta, sr_amp" >&2
    exit 4
    ;;
esac

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "ERROR: Dockerfile not found at: ${DOCKERFILE_PATH}" >&2
  echo "Expected Dockerfiles:" >&2
  echo "  ${DOCKERFILE_LR}" >&2
  echo "  ${DOCKERFILE_SR}" >&2
  exit 2
fi

image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

if [[ "${REBUILD}" == "1" ]] || ! image_exists "${IMAGE_NAME}"; then
  echo "[container] Using Dockerfile: ${DOCKERFILE_PATH}"
  echo "[container] Building image: ${IMAGE_NAME}"
  docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${REPO_ROOT}"
else
  echo "[container] Image exists: ${IMAGE_NAME} (use --rebuild to force rebuild)"
fi

echo "[container] Running pipeline inside container"
echo "[container] Repo root: ${REPO_ROOT}"
echo "[container] Config: ${CONFIG_ABS}"
echo "[container] Pipeline: ${PIPELINE_ID_RAW} (normalized: ${PIPELINE_KEY})"

# Optional Kraken2 DB mounts (host -> container)
KRAKEN_DB_HOST_HOSTPATH="$(jq_first "${CONFIG_ABS}" \
  '.host.mounts.kraken2_db_host' \
  '.host.kraken2.db_host' \
  '.host.kraken2_db_host' \
  || true
)"

KRAKEN_DB_CLASSIFY_HOSTPATH="$(jq_first "${CONFIG_ABS}" \
  '.host.mounts.kraken2_db_classify' \
  '.host.kraken2.db_classify' \
  '.host.kraken2_db_classify' \
  || true
)"

KRAKEN_DB_HOST_CONTAINERPATH="$(jq_first "${CONFIG_ABS}" \
  '.tools.kraken2.db_host' \
  '.tools.kraken2.db_host_container' \
  || true
)"
KRAKEN_DB_CLASSIFY_CONTAINERPATH="$(jq_first "${CONFIG_ABS}" \
  '.tools.kraken2.db_classify' \
  '.tools.kraken2.db_classify_container' \
  || true
)"

[[ -n "${KRAKEN_DB_HOST_CONTAINERPATH}" ]] || KRAKEN_DB_HOST_CONTAINERPATH="/db/host"
[[ -n "${KRAKEN_DB_CLASSIFY_CONTAINERPATH}" ]] || KRAKEN_DB_CLASSIFY_CONTAINERPATH="/db/classify"

DOCKER_ARGS=(
  run --rm
  -e STABIOM_IN_CONTAINER=1
  -v "${REPO_ROOT}:/work:rw"
  -v "/Users:/Users:rw"
  -w "/work"
)

if [[ "${NEEDS_DOCKER_SOCK}" == "1" ]]; then
  if [[ -S "/var/run/docker.sock" ]]; then
    DOCKER_ARGS+=( -v "/var/run/docker.sock:/var/run/docker.sock" )
  else
    echo "WARNING: /var/run/docker.sock not found on host; sr_amp qiime2 inner docker runs will not work." >&2
  fi
fi

# Add DB mounts if configured (read-only)
if [[ -n "${KRAKEN_DB_HOST_HOSTPATH}" ]]; then
  if [[ ! -d "${KRAKEN_DB_HOST_HOSTPATH}" ]]; then
    echo "ERROR: host.mounts.kraken2_db_host is set but directory does not exist: ${KRAKEN_DB_HOST_HOSTPATH}" >&2
    exit 5
  fi
  echo "[container] Mounting kraken2 host-removal DB: ${KRAKEN_DB_HOST_HOSTPATH} -> ${KRAKEN_DB_HOST_CONTAINERPATH} (ro)"
  DOCKER_ARGS+=( -v "${KRAKEN_DB_HOST_HOSTPATH}:${KRAKEN_DB_HOST_CONTAINERPATH}:ro" )
fi

if [[ -n "${KRAKEN_DB_CLASSIFY_HOSTPATH}" ]]; then
  if [[ ! -d "${KRAKEN_DB_CLASSIFY_HOSTPATH}" ]]; then
    echo "ERROR: host.mounts.kraken2_db_classify is set but directory does not exist: ${KRAKEN_DB_CLASSIFY_HOSTPATH}" >&2
    exit 5
  fi
  echo "[container] Mounting kraken2 classify DB: ${KRAKEN_DB_CLASSIFY_HOSTPATH} -> ${KRAKEN_DB_CLASSIFY_CONTAINERPATH} (ro)"
  DOCKER_ARGS+=( -v "${KRAKEN_DB_CLASSIFY_HOSTPATH}:${KRAKEN_DB_CLASSIFY_CONTAINERPATH}:ro" )
fi

DOCKER_ARGS+=( "${IMAGE_NAME}" bash "pipelines/stabiom_run.sh" --config "${CONFIG_ABS}" )

docker "${DOCKER_ARGS[@]}"
