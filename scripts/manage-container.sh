#!/usr/bin/env bash
# Lifecycle management for local dev/test containers of this image.
# Usage: scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test> [tag]
#
# "dev" is a single, deterministically-named, long-lived container
# (${CONTAINER_NAME}-dev, volume ${CONTAINER_NAME}-dev-data). "test" is
# disposable and supports several *concurrent* instances (e.g. several
# worktrees or CI jobs on one engine): every `create test` gets a fresh
# random hash appended to its container and volume names
# (${CONTAINER_NAME}-test-<hash>, ${CONTAINER_NAME}-test-data-<hash>) and an
# entry recording it in .manage-container-test.state (repo-root,
# gitignored, one line per live instance). `start`/`stop`/`delete test`
# resolve which instance to target from a TEST_HASH environment override, or
# from the state file when it holds exactly one entry - `create test` prints
# `TEST_HASH=<hash>` on success so a caller can pass it through explicitly.
#
# Every invocation, of any command and suffix, first sweeps the engine for
# zombie test resources (containers/volumes matching the test naming schema
# with no corresponding state file entry) and deletes them outright - and
# for a "test" invocation, only ("dev" invocations only observe/log them).
# It also identifies (but never touches) the dev container/volume and any
# container using this image under a name matching neither schema (may be
# prod or close-to-prod).
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
TEST_STATE_FILE="$ROOT_DIR/.manage-container-test.state"
TEST_STATE_LOCK="${TEST_STATE_FILE}.lock"

# Safety net: release a lock this process is still holding if it exits
# unexpectedly while a critical section is open. mkdir/rmdir are used
# instead of flock(1) because flock is not available on macOS.
trap 'rmdir "$TEST_STATE_LOCK" 2>/dev/null || true' EXIT

# Preserve caller-exported overrides (e.g. `FUSEKI_PORT=3031 ...`); .env.run
# must only fill in values the caller did not already set.
overridable_vars=(CONTAINER_NAME IMAGE_NAME IMAGE_TAG FUSEKI_PORT FUSEKI_ENDPOINT_HEALTH FUSEKI_CONFIG_VOLUME REQUIRE_LUCENE JVM_ARGS LOGGING)
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

IMAGE_NAME="${IMAGE_NAME:-fuseki}"
FUSEKI_PORT="${FUSEKI_PORT:-3030}"
FUSEKI_ENDPOINT_HEALTH="${FUSEKI_ENDPOINT_HEALTH:-/\$/ping}"

if [[ -n "${ENGINE:-}" ]]; then
  : # Caller specified ENGINE override
elif command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

TEST_CONTAINER_RE="^${CONTAINER_NAME}-test-[0-9a-f]+$"
TEST_VOLUME_RE="^${CONTAINER_NAME}-test-data-[0-9a-f]+$"
DEV_CONTAINER_NAME="${CONTAINER_NAME}-dev"
DEV_DATA_VOLUME="${CONTAINER_NAME}-dev-data"

# Generate a short unique identifier for a new test container/volume name
# pair. Prefers uuid4 hex (uuidgen); falls back to hashing wall-clock time,
# PID, and $RANDOM when uuidgen is unavailable.
generate_hash() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-'
  elif command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$(date +%s)-$$-$RANDOM-$RANDOM" | md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    printf '%s' "$(date +%s)-$$-$RANDOM-$RANDOM" | md5 -q
  else
    echo "ERROR: none of uuidgen, md5sum, or md5 is available to generate a unique test container hash." >&2
    exit 1
  fi
}

# True (exit 0) if something is already listening on 127.0.0.1:$1.
port_in_use() {
  (: >"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1
}

# Find a free port starting at $1, incrementing by 1 until one is free.
# Prints the resolved port and, if it differs from the request, a notice.
resolve_free_port() {
  local port="$1" original="$1" attempts=0 max_attempts=50
  while port_in_use "$port"; do
    attempts=$((attempts + 1))
    if ((attempts > max_attempts)); then
      echo "ERROR: no free port found in range ${original}-$((original + max_attempts))" >&2
      exit 1
    fi
    port=$((port + 1))
  done
  if [[ "$port" != "$original" ]]; then
    echo "[Manage] Port ${original} is already in use; using ${port} instead." >&2
  fi
  printf '%s' "$port"
}

# Return the newest local image tag matching "${IMAGE_NAME}:${1}" (by
# creation time, not semver), or empty if none exists.
latest_tag_matching() {
  "$ENGINE" images --format '{{.CreatedAt}}|{{.Tag}}' --filter "reference=${IMAGE_NAME}:${1}" 2>/dev/null \
    | sort -r | head -n1 | cut -d'|' -f2
}

# Resolve the newest local "<version>-dev" tag, building one if none exists.
resolve_latest_dev_tag() {
  local tag
  tag=$(latest_tag_matching '*-dev')
  if [[ -z "$tag" ]]; then
    echo "[Manage] No local image tag matching '${IMAGE_NAME}:*-dev' found; building one..." >&2
    bash "$ROOT_DIR/scripts/build-image.sh"
    tag=$(latest_tag_matching '*-dev')
  fi
  if [[ -z "$tag" ]]; then
    echo "ERROR: build completed but no '${IMAGE_NAME}:*-dev' image tag was produced." >&2
    exit 1
  fi
  printf '%s' "$tag"
}

# Resolve the newest local "<version>-test" tag, building one if none exists.
resolve_latest_test_tag() {
  local tag
  tag=$(latest_tag_matching '*-test')
  if [[ -z "$tag" ]]; then
    echo "[Manage] No local image tag matching '${IMAGE_NAME}:*-test' found; building one..." >&2
    FOR_TESTS=true bash "$ROOT_DIR/scripts/build-image.sh"
    tag=$(latest_tag_matching '*-test')
  fi
  if [[ -z "$tag" ]]; then
    echo "ERROR: build completed but no '${IMAGE_NAME}:*-test' image tag was produced." >&2
    exit 1
  fi
  printf '%s' "$tag"
}

# Resolve the image tag to use for $1 (dev|test): explicit CLI tag argument >
# IMAGE_TAG environment override > suffix-based default (newest local
# "*-dev"/"*-test" tag, building one if none exists).
resolve_tag() {
  if [[ -n "$TAG_OVERRIDE" ]]; then
    printf '%s' "$TAG_OVERRIDE"
  elif [[ -n "${IMAGE_TAG:-}" ]]; then
    printf '%s' "$IMAGE_TAG"
  elif [[ "$1" == "test" ]]; then
    resolve_latest_test_tag
  else
    resolve_latest_dev_tag
  fi
}

# Guarantee "${IMAGE_NAME}:${2}" exists locally, building it with the exact
# requested tag if it does not. Handles the case where an explicit tag (CLI
# argument or IMAGE_TAG override) names an image that has not been built yet;
# resolve_latest_*_tag already guarantees the auto-resolved case exists.
ensure_image() {
  local suffix="$1" tag="$2"
  local image="${IMAGE_NAME}:${tag}"
  if "$ENGINE" image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi
  echo "[Manage] Image '$image' not found locally; building it..."
  if [[ "$suffix" == "test" ]]; then
    FOR_TESTS=true IMAGE_TAG="$tag" bash "$ROOT_DIR/scripts/build-image.sh"
  else
    IMAGE_TAG="$tag" bash "$ROOT_DIR/scripts/build-image.sh"
  fi
  if ! "$ENGINE" image inspect "$image" >/dev/null 2>&1; then
    echo "ERROR: build completed but image '$image' is still not available locally." >&2
    exit 1
  fi
}

# Current git branch, best-effort ("unknown" if unavailable/detached without
# a CI ref hint). Purely informational: recorded in the test state file
# alongside the hash for human diagnosis, never used to resolve identity.
current_branch() {
  local branch
  branch=$(git -C "$ROOT_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" ]]; then
    branch="${GITHUB_REF_NAME:-${CI_COMMIT_REF_NAME:-unknown}}"
  fi
  printf '%s' "$branch"
}

# Human-readable size of a named volume's data (best effort). On engines
# where the volume's mountpoint is not directly visible to this host (e.g.
# podman-machine on macOS, which runs inside a Linux VM), this cannot be
# measured locally and reports "unknown" - cosmetic only, never fatal.
volume_size() {
  local vol="$1" mountpoint
  mountpoint=$("$ENGINE" volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null || true)
  if [[ -n "$mountpoint" && -d "$mountpoint" ]]; then
    du -sh "$mountpoint" 2>/dev/null | cut -f1
  else
    echo "unknown"
  fi
}

# Consolidated, uniformly-formatted INFO line for any container or volume the
# sweep identifies. $2 is "container" or "volume"; $3 (state) applies only to
# containers, $4 (size) only to volumes - pass "" for the inapplicable one.
# $5 (tracked) is one of: true, false, dev (a dev resource; the state file
# does not apply to it), other (neither schema; not this script's to track).
log_resource() {
  local name="$1" type="$2" state="$3" size="$4" tracked="$5" extra=""
  [[ "$type" == "container" ]] && extra=" state=${state}"
  [[ "$type" == "volume" ]] && extra=" size=${size}"
  echo "[Manage] INFO: name='${name}' type=${type}${extra} tracked=${tracked}"
}

# Serializes state file mutations (add/remove entry) across concurrent
# invocations sharing this checkout. mkdir is atomic on every POSIX
# filesystem; no extra tooling (flock, jq, sqlite, ...) is required.
acquire_state_lock() {
  local waited=0
  while ! mkdir "$TEST_STATE_LOCK" 2>/dev/null; do
    waited=$((waited + 1))
    if ((waited > 100)); then
      echo "ERROR: could not acquire state lock '$TEST_STATE_LOCK' after 10s. If no other invocation is active, a crashed run left it behind - remove it manually." >&2
      exit 1
    fi
    sleep 0.1
  done
}

release_state_lock() {
  rmdir "$TEST_STATE_LOCK" 2>/dev/null || true
}

# Print all state file entries, one per line: hash<TAB>port<TAB>branch<TAB>image<TAB>tag
state_entries() {
  if [[ -f "$TEST_STATE_FILE" ]]; then cat "$TEST_STATE_FILE"; fi
}

# Register a live test instance. Called before the volume/container are
# created, so a crash between the two leaves a discoverable (if stale) trail
# instead of an unregistered zombie, and no concurrent invocation can mint
# the same hash/port pair unnoticed.
state_add_entry() {
  local hash="$1" port="$2" branch="$3" image="$4" tag="$5"
  acquire_state_lock
  printf '%s\t%s\t%s\t%s\t%s\n' "$hash" "$port" "$branch" "$image" "$tag" >> "$TEST_STATE_FILE"
  release_state_lock
}

# Remove the entry for hash $1, if present. Called only after both the
# container and the volume it described have been confirmed gone.
state_remove_entry() {
  local hash="$1"
  acquire_state_lock
  if [[ -f "$TEST_STATE_FILE" ]]; then
    awk -F'\t' -v h="$hash" '$1 != h' "$TEST_STATE_FILE" > "${TEST_STATE_FILE}.tmp"
    mv "${TEST_STATE_FILE}.tmp" "$TEST_STATE_FILE"
    [[ -s "$TEST_STATE_FILE" ]] || rm -f "$TEST_STATE_FILE"
  fi
  release_state_lock
}

# Drop entries whose container AND volume are both already gone (e.g. a
# concurrent 'delete' won the race, or something was removed out of band).
state_prune_stale_entries() {
  local hash port branch image tag container volume
  while IFS=$'\t' read -r hash port branch image tag; do
    [[ -z "$hash" ]] && continue
    container="${CONTAINER_NAME}-test-${hash}"
    volume="${CONTAINER_NAME}-test-data-${hash}"
    if ! "$ENGINE" inspect "$container" >/dev/null 2>&1 && ! "$ENGINE" volume inspect "$volume" >/dev/null 2>&1; then
      echo "[Manage] INFO: state file entry for hash '${hash}' has no matching container or volume; removing the stale record."
      state_remove_entry "$hash"
    fi
  done < <(state_entries)
}

# Build the run/create argument array in $ARGS for the target suffix.
# "dev" mounts the persistent, deterministically-named data volume and the
# config volume from .env.run. "test" mounts a dedicated, disposable data
# volume and this repo's own config/ directory - never the dev volume or a
# caller-supplied config.
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
    if [[ -z "${FUSEKI_CONFIG_VOLUME:-}" ]]; then
      echo "ERROR: FUSEKI_CONFIG_VOLUME is not set in .env.run" >&2
      exit 1
    fi
    ARGS+=(-v "${DEV_DATA_VOLUME}:/fuseki/data")
    ARGS+=(-v "${FUSEKI_CONFIG_VOLUME}:/fuseki/config:ro")
  else
    ARGS+=(-v "${TEST_DATA_VOLUME}:/fuseki/data")
    ARGS+=(-v "${ROOT_DIR}/config:/fuseki/config:ro")
  fi

  ARGS+=("$image")
}

# Runs unconditionally at the start of every invocation, for every command
# and suffix. Identifies:
#   a) test-schema containers/volumes  - deleted if untracked AND this
#      invocation's suffix is "test" (zombies must not persist); logged
#      either way.
#   b) the dev container/volume        - identified/logged only, never
#      auto-deleted (used separately by the create-time collision prompt).
#   c) containers using this image under a name matching neither schema -
#      identified/logged only, never touched (may be prod/close-to-prod).
#   d) entries in the state file       - the "tracked" set for (a); entries
#      with no matching container/volume are pruned first.
sweep_zombies() {
  state_prune_stale_entries

  local registered=" " hash
  while IFS=$'\t' read -r hash _; do
    [[ -n "$hash" ]] && registered="${registered}${hash} "
  done < <(state_entries)

  local name status size tracked
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    hash="${name#"${CONTAINER_NAME}"-test-}"
    status=$("$ENGINE" inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo unknown)
    [[ "$status" == "running" ]] && status=running || status=stopped
    if [[ "$registered" == *" ${hash} "* ]]; then tracked=true; else tracked=false; fi
    log_resource "$name" container "$status" "" "$tracked"
    if [[ "$tracked" == "false" && "$SUFFIX" == "test" ]]; then
      echo "[Manage] INFO: untracked test container '${name}' found; removing it (zombies must not persist)."
      TARGET_NAME="$name"
      TEST_DATA_VOLUME="${CONTAINER_NAME}-test-data-${hash}"
      delete_container
    fi
  done < <("$ENGINE" ps -a --format '{{.Names}}' 2>/dev/null | grep -E "$TEST_CONTAINER_RE" || true)

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    "$ENGINE" volume inspect "$name" >/dev/null 2>&1 || continue # already removed above alongside its container
    hash="${name#"${CONTAINER_NAME}"-test-data-}"
    size=$(volume_size "$name")
    if [[ "$registered" == *" ${hash} "* ]]; then tracked=true; else tracked=false; fi
    log_resource "$name" volume "" "$size" "$tracked"
    if [[ "$tracked" == "false" && "$SUFFIX" == "test" ]]; then
      echo "[Manage] INFO: untracked test volume '${name}' found; removing it (zombies must not persist)."
      TARGET_NAME="${CONTAINER_NAME}-test-${hash}"
      TEST_DATA_VOLUME="$name"
      delete_container
    fi
  done < <("$ENGINE" volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$TEST_VOLUME_RE" || true)

  if "$ENGINE" inspect "$DEV_CONTAINER_NAME" >/dev/null 2>&1; then
    status=$("$ENGINE" inspect --format '{{.State.Status}}' "$DEV_CONTAINER_NAME" 2>/dev/null || echo unknown)
    [[ "$status" == "running" ]] && status=running || status=stopped
    log_resource "$DEV_CONTAINER_NAME" container "$status" "" dev
  fi
  if "$ENGINE" volume inspect "$DEV_DATA_VOLUME" >/dev/null 2>&1; then
    log_resource "$DEV_DATA_VOLUME" volume "" "$(volume_size "$DEV_DATA_VOLUME")" dev
  fi

  local image
  while IFS=$'\t' read -r name image; do
    [[ -z "$name" ]] && continue
    [[ "$image" == "${IMAGE_NAME}:"* || "$image" == */"${IMAGE_NAME}:"* ]] || continue
    [[ "$name" =~ $TEST_CONTAINER_RE ]] && continue
    [[ "$name" == "$DEV_CONTAINER_NAME" ]] && continue
    status=$("$ENGINE" inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo unknown)
    [[ "$status" == "running" ]] && status=running || status=stopped
    log_resource "$name" container "$status" "" other
  done < <("$ENGINE" ps -a --format '{{.Names}}\t{{.Image}}' 2>/dev/null || true)
}

# Resolve TARGET_NAME/TEST_DATA_VOLUME for a start/stop/delete on an existing
# test instance. TEST_HASH, if exported by the caller, selects the instance
# directly - required once more than one is tracked concurrently (e.g.
# several agents running the test suite against the same checkout). With no
# override, falls back to the state file's one entry; zero or several
# entries without an explicit TEST_HASH is an error.
resolve_test_target() {
  local hash
  if [[ -n "${TEST_HASH:-}" ]]; then
    hash="$TEST_HASH"
  else
    local count=0 only_hash=""
    while IFS=$'\t' read -r hash_field _; do
      [[ -z "$hash_field" ]] && continue
      count=$((count + 1))
      only_hash="$hash_field"
    done < <(state_entries)
    if [[ "$count" -eq 0 ]]; then
      echo "ERROR: no tracked test container found ($TEST_STATE_FILE is empty or missing). Nothing to $COMMAND." >&2
      exit 1
    elif [[ "$count" -gt 1 ]]; then
      echo "ERROR: multiple tracked test containers exist; set TEST_HASH=<hash> to select one. Currently tracked:" >&2
      state_entries | cut -f1 >&2
      exit 1
    fi
    hash="$only_hash"
  fi
  TARGET_NAME="${CONTAINER_NAME}-test-${hash}"
  TEST_DATA_VOLUME="${CONTAINER_NAME}-test-data-${hash}"
  local entry_port
  entry_port=$(state_entries | awk -F'\t' -v h="$hash" '$1 == h { print $2 }')
  [[ -n "$entry_port" ]] && FUSEKI_PORT="$entry_port"
}

# Dev only: a container by this name already exists. Offers to upgrade it in
# place (reuses upgrade_container()) or leave it untouched, instead of
# failing outright. Reads from /dev/tty so it still prompts even if the
# caller captured this script's stdout; defaults to the safe (no-op) choice
# after 10s so this can be invoked unattended (e.g. from CI or another
# script) without hanging.
prompt_dev_collision() {
  echo "[Manage] INFO: container '$TARGET_NAME' already exists."
  local choice=""
  { read -r -t 10 -p "[Manage] [u]pgrade existing container in place (recommended) / [e]xit without changes (safe, default in 10s): " choice < /dev/tty; } 2>/dev/null || true
  choice=$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')
  case "$choice" in
  u | upgrade)
    upgrade_container
    ;;
  *)
    echo "[Manage] INFO: exiting without changes; '$TARGET_NAME' left as-is."
    ;;
  esac
}

create_container() {
  if [[ "$SUFFIX" == "test" ]]; then
    local hash tag
    hash=$(generate_hash)
    TARGET_NAME="${CONTAINER_NAME}-test-${hash}"
    TEST_DATA_VOLUME="${CONTAINER_NAME}-test-data-${hash}"

    if "$ENGINE" inspect "$TARGET_NAME" >/dev/null 2>&1 || "$ENGINE" volume inspect "$TEST_DATA_VOLUME" >/dev/null 2>&1; then
      echo "ERROR: freshly generated name '$TARGET_NAME' unexpectedly already exists (hash collision). Re-run to generate a new one." >&2
      exit 1
    fi

    tag=$(resolve_tag "$SUFFIX")
    ensure_image "$SUFFIX" "$tag"
    FUSEKI_PORT=$(resolve_free_port "$FUSEKI_PORT")

    # Record intent before creating anything: a crash between here and a
    # successful `run` still leaves a discoverable (if stale) trail, and no
    # concurrent invocation can mint the same hash/port pair unnoticed.
    state_add_entry "$hash" "$FUSEKI_PORT" "$(current_branch)" "$IMAGE_NAME" "$tag"

    "$ENGINE" volume create "$TEST_DATA_VOLUME" >/dev/null
    build_container_args "${IMAGE_NAME}:${tag}"
    "$ENGINE" run -d "${ARGS[@]}"

    echo "TEST_HASH=${hash}"
    echo "[Manage] Container '$TARGET_NAME' created and started from ${IMAGE_NAME}:${tag}."
    echo "[Manage] Health endpoint: http://localhost:${FUSEKI_PORT}${FUSEKI_ENDPOINT_HEALTH}"
    return
  fi

  # dev
  if "$ENGINE" inspect "$TARGET_NAME" >/dev/null 2>&1; then
    prompt_dev_collision
    return
  fi

  local tag
  tag=$(resolve_tag "$SUFFIX")
  ensure_image "$SUFFIX" "$tag"
  FUSEKI_PORT=$(resolve_free_port "$FUSEKI_PORT")
  # Idempotent: reuses the volume if it already exists (dev data persists
  # across recreate/upgrade), creates it on first use otherwise.
  "$ENGINE" volume create "$DEV_DATA_VOLUME" >/dev/null
  build_container_args "${IMAGE_NAME}:${tag}"
  "$ENGINE" run -d "${ARGS[@]}"
  echo "[Manage] Container '$TARGET_NAME' created and started from ${IMAGE_NAME}:${tag}."
  echo "[Manage] Health endpoint: http://localhost:${FUSEKI_PORT}${FUSEKI_ENDPOINT_HEALTH}"
}

start_container() {
  "$ENGINE" start "$TARGET_NAME"
  echo "[Manage] Container '$TARGET_NAME' started."
}

stop_container() {
  "$ENGINE" stop "$TARGET_NAME"
  echo "[Manage] Container '$TARGET_NAME' stopped."
}

# Tolerant of partial/total absence and of individual engine-call failure so
# it can be reused both for the explicit 'delete' command and zombie
# sweeping, and so a caller relying on it for teardown (e.g. the integration
# test's EXIT trap) can depend on it never aborting mid-cleanup. The state
# file entry (test only) is removed only once both the container and the
# volume are confirmed gone - never before, so a failed cleanup remains
# visible and retryable.
delete_container() {
  if [[ "$SUFFIX" == "dev" ]]; then
    if "$ENGINE" inspect "$TARGET_NAME" >/dev/null 2>&1; then
      "$ENGINE" rm -f "$TARGET_NAME" >/dev/null 2>&1 || true
      echo "[Manage] Container '$TARGET_NAME' deleted (volumes untouched)."
    else
      echo "[Manage] Container '$TARGET_NAME' does not exist; nothing to delete."
    fi
    return 0
  fi

  local hash="${TARGET_NAME#"${CONTAINER_NAME}"-test-}"
  local container_gone=true volume_gone=true

  if "$ENGINE" inspect "$TARGET_NAME" >/dev/null 2>&1; then
    if "$ENGINE" rm -f "$TARGET_NAME" >/dev/null 2>&1; then
      echo "[Manage] Container '$TARGET_NAME' deleted."
    else
      echo "[Manage] WARNING: failed to delete container '$TARGET_NAME'." >&2
      container_gone=false
    fi
  fi

  if "$ENGINE" volume inspect "$TEST_DATA_VOLUME" >/dev/null 2>&1; then
    if "$ENGINE" volume rm -f "$TEST_DATA_VOLUME" >/dev/null 2>&1; then
      echo "[Manage] Volume '$TEST_DATA_VOLUME' deleted."
    else
      echo "[Manage] WARNING: failed to delete volume '$TEST_DATA_VOLUME'." >&2
      volume_gone=false
    fi
  fi

  if [[ "$container_gone" == "true" && "$volume_gone" == "true" ]]; then
    state_remove_entry "$hash"
  else
    echo "[Manage] WARNING: leaving the state file entry for hash '${hash}' in place; retry delete to finish cleanup." >&2
  fi
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
  ensure_image "dev" "$tag"
  echo "[Manage] Upgrading '$TARGET_NAME' (running: $state) to ${IMAGE_NAME}:${tag}..."

  "$ENGINE" rm -f "$TARGET_NAME"
  FUSEKI_PORT=$(resolve_free_port "$FUSEKI_PORT")
  build_container_args "${IMAGE_NAME}:${tag}"

  if [[ "$state" == "true" ]]; then
    "$ENGINE" run -d "${ARGS[@]}"
    echo "[Manage] Container '$TARGET_NAME' upgraded and started."
  else
    "$ENGINE" create "${ARGS[@]}"
    echo "[Manage] Container '$TARGET_NAME' upgraded in stopped state."
  fi
}

# Sweep first, unconditionally, for every command and suffix.
sweep_zombies

# Resolve the target for this invocation. "create test" resolves its own
# TARGET_NAME/TEST_DATA_VOLUME internally once a fresh hash exists.
if [[ "$SUFFIX" == "dev" ]]; then
  TARGET_NAME="$DEV_CONTAINER_NAME"
elif [[ "$COMMAND" != "create" ]]; then
  resolve_test_target
fi

case "$COMMAND" in
create) create_container ;;
start) start_container ;;
stop) stop_container ;;
delete) delete_container ;;
upgrade) upgrade_container ;;
esac
