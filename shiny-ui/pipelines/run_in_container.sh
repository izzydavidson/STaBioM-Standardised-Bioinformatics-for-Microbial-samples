#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  pipelines/run_in_container.sh --config <path/to/config.json> [--rebuild]

What it does:
  - Reads pipeline_id from the config
  - Picks Dockerfile + image name based on pipeline_id
      lr_meta/lr_amp -> pipelines/container/dockerfile.lr -> stabiom-tools-lr:dev
      sr_meta/sr_amp -> pipelines/container/dockerfile.sr -> stabiom-tools-sr:dev
  - Builds the image if missing (or if --rebuild)
  - Runs pipelines/stabiom_run.sh --config <config> inside that container
  - For sr_* pipelines, mounts the host docker socket so sr_amp can docker-run qiime2

Notes:
  - It will print the exact IMAGE_NAME it used so you can reuse it in manual docker run commands.
EOF
  exit 1
}

CONFIG_PATH=""
REBUILD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_PATH="${2:-}"; shift 2 ;;
    --rebuild) REBUILD="1"; shift 1 ;;
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
DISPATCHER_IN_CONTAINER="pipelines/stabiom_run.sh"

CONFIG_ABS="$(cd "$(dirname "${CONFIG_PATH}")" && pwd)/$(basename "${CONFIG_PATH}")"

PIPELINE_ID_RAW="$(jq -r '
  .pipeline_id
  // .pipelineId
  // .pipeline.id
  // .pipeline.pipeline_id
  // empty
' "${CONFIG_ABS}")"

PIPELINE_ID_RAW="$(printf "%s" "${PIPELINE_ID_RAW}" | tr -d '\r\n')"
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
  exit 2
fi

image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

if [[ "${REBUILD}" == "1" ]] || ! image_exists "${IMAGE_NAME}"; then
  echo "[container] Using Dockerfile: ${DOCKERFILE_PATH}"
  echo "[container] Building image: ${IMAGE_NAME}"
  docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${REPO_ROOT}"
else
  echo "[container] Image exists: ${IMAGE_NAME} (use --rebuild to force rebuild)"
fi

# Prefer passing config as /work/... if it lives under repo root (cleaner in-container)
CONFIG_IN_CONTAINER="${CONFIG_ABS}"
if [[ "${CONFIG_ABS}" == "${REPO_ROOT}"* ]]; then
  CONFIG_IN_CONTAINER="/work${CONFIG_ABS#${REPO_ROOT}}"
fi

echo "[container] Running pipeline inside container"
echo "[container] Repo root (host): ${REPO_ROOT}"
echo "[container] Config (host): ${CONFIG_ABS}"
echo "[container] Config (in-container): ${CONFIG_IN_CONTAINER}"
echo "[container] Pipeline: ${PIPELINE_ID_RAW} (normalized: ${PIPELINE_KEY})"
echo "[container] Image: ${IMAGE_NAME}"

DOCKER_ARGS=(
  run --rm
  -e STABIOM_IN_CONTAINER=1
  -v "${REPO_ROOT}:/work:rw"
  -w "/work"
)

# On macOS, most paths are under /Users; mount it so absolute host paths in config still work.
if [[ -d "/Users" ]]; then
  DOCKER_ARGS+=( -v "/Users:/Users:rw" )
fi
if [[ -d "/Volumes" ]]; then
  DOCKER_ARGS+=( -v "/Volumes:/Volumes:rw" )
fi

if [[ "${NEEDS_DOCKER_SOCK}" == "1" ]]; then
  if [[ -S "/var/run/docker.sock" ]]; then
    DOCKER_ARGS+=( -v "/var/run/docker.sock:/var/run/docker.sock" )
  else
    echo "WARNING: /var/run/docker.sock not found on host; sr_amp inner docker runs will not work." >&2
  fi
fi

DOCKER_ARGS+=( "${IMAGE_NAME}" bash "${DISPATCHER_IN_CONTAINER}" --config "${CONFIG_IN_CONTAINER}" )

docker "${DOCKER_ARGS[@]}"
