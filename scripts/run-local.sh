#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Load .env.run if it exists
if [ -f "$ROOT_DIR/.env.run" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env.run"
  set +a
fi
IMAGE_NAME="${IMAGE_NAME:-fuseki}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
CONTAINER_NAME="${CONTAINER_NAME:-fuseki}"
FUSEKI_PORT="${FUSEKI_PORT:-3030}"

# Named volume for persistent data. Works on Podman/Docker including macOS Colima.
# Override with an absolute host path only when you have confirmed filesystem sharing.
FUSEKI_DATA_VOLUME="${FUSEKI_DATA_VOLUME:-fuseki-data-dev}"

# Optional config overrides: set these to absolute host paths to mount custom files.
# Leave unset to use the defaults baked into the image.
FUSEKI_CONFIG_FILE="${FUSEKI_CONFIG_FILE:-}"
FUSEKI_SHIRO_FILE="${FUSEKI_SHIRO_FILE:-}"
FUSEKI_LOG4J2_FILE="${FUSEKI_LOG4J2_FILE:-}"

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

"$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

EXTRA_MOUNTS=()
[[ -n "$FUSEKI_CONFIG_FILE" ]] && EXTRA_MOUNTS+=("-v" "${FUSEKI_CONFIG_FILE}:/fuseki/config:ro")
[[ -n "$FUSEKI_SHIRO_FILE"  ]] && EXTRA_MOUNTS+=("-v" "${FUSEKI_SHIRO_FILE}:/fuseki/config/shiro.ini:ro")
[[ -n "$FUSEKI_LOG4J2_FILE" ]] && EXTRA_MOUNTS+=("-v" "${FUSEKI_LOG4J2_FILE}:/fuseki/config/log4j2.xml:ro")
EXTRA_ENVS=()
[[ -n "${JVM_ARGS:-}" ]] && EXTRA_ENVS+=("-e" "JVM_ARGS=${JVM_ARGS}")
[[ -n "${LOGGING:-}" ]] && EXTRA_ENVS+=("-e" "LOGGING=${LOGGING}")

"$ENGINE" run -d \
  --name "$CONTAINER_NAME" \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p "${FUSEKI_PORT}:3030" \
  -v "${FUSEKI_DATA_VOLUME}:/fuseki/data" \
  "${EXTRA_ENVS[@]+"${EXTRA_ENVS[@]}"}" \
  "${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"}" \
  "${IMAGE_NAME}:${IMAGE_TAG}"

echo "Container started: ${CONTAINER_NAME}"
echo "Health endpoint: http://localhost:${FUSEKI_PORT}/\$/ping"
