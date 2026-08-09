#!/usr/bin/env bash
# Lifecycle management for local dev/test containers of this image.
# Usage: scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test> [tag]
set -euo pipefail

usage() {
  echo "Usage: $0 <create|start|stop|delete|upgrade> <dev|test> [tag]" >&2
  exit 1
}

[[ $# -eq 2 || $# -eq 3 ]] || usage
COMMAND="$1"
SUFFIX="$2"
TAG_OVERRIDE="${3:-}"

case "$COMMAND" in
create | start | stop | delete | upgrade) ;;
*) usage ;;
esac

case "$SUFFIX" in
dev | test) ;;
*) usage ;;
esac

if [[ -n "$TAG_OVERRIDE" && "$COMMAND" != "create" && "$COMMAND" != "upgrade" ]]; then
  echo "ERROR: a tag argument is only valid with 'create' or 'upgrade'" >&2
  exit 1
fi

if [[ "$COMMAND" == "upgrade" && "$SUFFIX" == "test" ]]; then
  echo "ERROR: 'upgrade' only targets the dev container; test containers are short-lived and disposable (use 'create test' instead)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Preserve caller-exported overrides (e.g. `FUSEKI_PORT=3031 ...`); .env.run
# must only fill in values the caller did not already set.
overridable_vars=(CONTAINER_NAME IMAGE_NAME IMAGE_TAG FUSEKI_PORT FUSEKI_DATA_VOLUME FUSEKI_CONFIG_VOLUME REQUIRE_LUCENE JVM_ARGS LOGGING)
for var in "${overridable_vars[@]}"; do
  if [ -n "${!var+x}" ]; then
    eval "_override_${var}=\${${var}}"
  fi
done

if [ -f "$ROOT_DIR/.env.run" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env.run"
  set +a
fi

for var in "${overridable_vars[@]}"; do
  override_name="_override_${var}"
  if [ -n "${!override_name+x}" ]; then
    eval "${var}=\${${override_name}}"
  fi
done

if [ -z "${CONTAINER_NAME:-}" ]; then
  echo "ERROR: CONTAINER_NAME is not set in .env.run" >&2
  exit 1
fi

# Container name is always CONTAINER_NAME + suffix. No other naming is allowed.
TARGET_NAME="${CONTAINER_NAME}-${SUFFIX}"
IMAGE_NAME="${IMAGE_NAME:-fuseki}"
FUSEKI_PORT="${FUSEKI_PORT:-3030}"

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

# Resolve the newest local "<version>-dev" tag for IMAGE_NAME (most recently
# built, not highest version number) to use as the default dev image.
resolve_latest_dev_tag() {
  local tag
  tag=$("$ENGINE" images --format '{{.CreatedAt}}|{{.Tag}}' --filter "reference=${IMAGE_NAME}:*-dev" 2>/dev/null \
    | sort -r | head -n1 | cut -d'|' -f2)
  if [[ -z "$tag" ]]; then
    echo "ERROR: no local image tag matching '${IMAGE_NAME}:*-dev' found. Build one (scripts/build-image.sh) or pass an explicit tag." >&2
    exit 1
  fi
  printf '%s' "$tag"
}

# Resolve the image tag to use for $1 (dev|test): explicit CLI tag argument >
# IMAGE_TAG environment override > suffix-based default (test: "latest",
# dev: newest local "*-dev" tag).
resolve_tag() {
  if [[ -n "$TAG_OVERRIDE" ]]; then
    printf '%s' "$TAG_OVERRIDE"
  elif [[ -n "${IMAGE_TAG:-}" ]]; then
    printf '%s' "$IMAGE_TAG"
  elif [[ "$1" == "test" ]]; then
    printf 'latest'
  else
    resolve_latest_dev_tag
  fi
}

# Build the run/create argument array in $ARGS for the target suffix.
# "dev" mounts persistent data and config volumes from .env.run.
# "test" stays ephemeral: no volumes, defaults baked into the image.
build_container_args() {
  local image="$1"
  ARGS=(
    --name "$TARGET_NAME"
    --read-only
    --tmpfs /fuseki/run:mode=1777
    --tmpfs /tmp:mode=1777
    -p "${FUSEKI_PORT}:3030"
  )
  [[ -n "${REQUIRE_LUCENE:-}" ]] && ARGS+=(-e "REQUIRE_LUCENE=${REQUIRE_LUCENE}")
  [[ -n "${JVM_ARGS:-}" ]] && ARGS+=(-e "JVM_ARGS=${JVM_ARGS}")
  [[ -n "${LOGGING:-}" ]] && ARGS+=(-e "LOGGING=${LOGGING}")

  if [[ "$SUFFIX" == "dev" ]]; then
    if [[ -z "${FUSEKI_DATA_VOLUME:-}" ]]; then
      echo "ERROR: FUSEKI_DATA_VOLUME is not set in .env.run" >&2
      exit 1
    fi
    if [[ -z "${FUSEKI_CONFIG_VOLUME:-}" ]]; then
      echo "ERROR: FUSEKI_CONFIG_VOLUME is not set in .env.run" >&2
      exit 1
    fi
    ARGS+=(-v "${FUSEKI_DATA_VOLUME}:/fuseki/data")
    ARGS+=(-v "${FUSEKI_CONFIG_VOLUME}:/fuseki/config:ro")
  fi

  ARGS+=("$image")
}

create_container() {
  local tag
  tag=$(resolve_tag "$SUFFIX")
  "$ENGINE" rm -f "$TARGET_NAME" >/dev/null 2>&1 || true
  build_container_args "${IMAGE_NAME}:${tag}"
  "$ENGINE" run -d "${ARGS[@]}"
  echo "[Manage] Container '$TARGET_NAME' created and started from ${IMAGE_NAME}:${tag}."
  echo "[Manage] Health endpoint: http://localhost:${FUSEKI_PORT}/\$/ping"
}

start_container() {
  "$ENGINE" start "$TARGET_NAME"
  echo "[Manage] Container '$TARGET_NAME' started."
}

stop_container() {
  "$ENGINE" stop "$TARGET_NAME"
  echo "[Manage] Container '$TARGET_NAME' stopped."
}

delete_container() {
  "$ENGINE" rm -f "$TARGET_NAME"
  echo "[Manage] Container '$TARGET_NAME' deleted (volumes untouched)."
}

# Always targets the dev container; test containers are short-lived and
# recreated via 'create test' instead of being upgraded in place.
upgrade_container() {
  if ! "$ENGINE" inspect "$TARGET_NAME" >/dev/null 2>&1; then
    echo "[Manage] Container '$TARGET_NAME' does not exist. Nothing to upgrade."
    return 0
  fi

  local state tag
  state=$("$ENGINE" inspect --format='{{.State.Running}}' "$TARGET_NAME")
  tag=$(resolve_tag "dev")
  echo "[Manage] Upgrading '$TARGET_NAME' (running: $state) to ${IMAGE_NAME}:${tag}..."

  "$ENGINE" rm -f "$TARGET_NAME"
  build_container_args "${IMAGE_NAME}:${tag}"

  if [[ "$state" == "true" ]]; then
    "$ENGINE" run -d "${ARGS[@]}"
    echo "[Manage] Container '$TARGET_NAME' upgraded and started."
  else
    "$ENGINE" create "${ARGS[@]}"
    echo "[Manage] Container '$TARGET_NAME' upgraded in stopped state."
  fi
}

case "$COMMAND" in
create) create_container ;;
start) start_container ;;
stop) stop_container ;;
delete) delete_container ;;
upgrade) upgrade_container ;;
esac
