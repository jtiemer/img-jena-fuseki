#!/usr/bin/env bash
# Synchronous script to upgrade a running/stopped container to the latest image tag
# while fully preserving all volumes (data, configs), port mappings, tmpfs mounts, and state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Resolve container engine
if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

# 2. Load container configuration strictly from .env.run file
if [ -f "$ROOT_DIR/.env.run" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env.run"
fi

if [ -z "${CONTAINER_NAME:-}" ]; then
  echo "ERROR: CONTAINER_NAME is not set in .env.run" >&2
  exit 1
fi

IMAGE_NAME="${IMAGE_NAME:-fuseki}"

echo "[Upgrade] Checking container '$CONTAINER_NAME'..."
if ! "$ENGINE" inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "[Upgrade] Container '$CONTAINER_NAME' does not exist. Nothing to upgrade."
  exit 0
fi

# 3. Record running state of the container
state=$( "$ENGINE" inspect --format='{{.State.Running}}' "$CONTAINER_NAME" )
echo "[Upgrade] Found container. Running state: $state"

# 4. Extract active Mounts (Volumes and Bind Mounts) supporting multiple mounts
echo "[Upgrade] Extracting volume and bind-mount configurations..."
mounts_args=()
while IFS= read -r mount; do
  if [[ -n "$mount" ]]; then
    mounts_args+=("-v" "$mount")
  fi
done < <( "$ENGINE" inspect --format='{{json .Mounts}}' "$CONTAINER_NAME" | jq -r 'if . == null then empty else .[] | if .Type == "volume" then "\(.Name):\(.Destination)\(if .RW == false then ":ro" else "" end)" else "\(.Source):\(.Destination)\(if .RW == false then ":ro" else "" end)" end end' )

# 5. Extract active Port Bindings
echo "[Upgrade] Extracting host port mappings..."
ports_args=()
while IFS= read -r port; do
  if [[ -n "$port" ]]; then
    ports_args+=("-p" "$port")
  fi
done < <( "$ENGINE" inspect --format='{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" | jq -r 'to_entries[] | "\(.value[0].HostPort):\(.key)"' | sed 's/<nil>//g' | sed 's/^://g' )

# 6. Extract active Tmpfs Mounts
echo "[Upgrade] Extracting tmpfs configurations..."
tmpfs_args=()
while IFS= read -r tmpfs; do
  if [[ -n "$tmpfs" ]]; then
    tmpfs_args+=("--tmpfs" "$tmpfs")
  fi
done < <( "$ENGINE" inspect --format='{{json .HostConfig.Tmpfs}}' "$CONTAINER_NAME" | jq -r 'to_entries[] | "\(.key):\(.value)"' )

# 7. Extract active Read-only Rootfs status
readonly_flag=$( "$ENGINE" inspect --format='{{.HostConfig.ReadonlyRootfs}}' "$CONTAINER_NAME" )
readonly_args=()
if [[ "$readonly_flag" == "true" ]]; then
  readonly_args+=("--read-only")
fi

# 8. Stop the old container if it is currently running
if [[ "$state" == "true" ]]; then
  echo "[Upgrade] Stopping running container '$CONTAINER_NAME'..."
  "$ENGINE" stop "$CONTAINER_NAME"
fi

# 9. Delete the old container instance
echo "[Upgrade] Deleting container '$CONTAINER_NAME' (leaving volumes untouched)..."
"$ENGINE" rm "$CONTAINER_NAME"

# 10. Recreate the container using the updated 'latest' image tag in the matching state
target_image="${IMAGE_NAME}:latest"
echo "[Upgrade] Re-creating container '$CONTAINER_NAME' using image '$target_image'..."

if [[ "$state" == "true" ]]; then
  # Relaunch and start running in detached mode
  "$ENGINE" run -d \
    --name "$CONTAINER_NAME" \
    "${readonly_args[@]+"${readonly_args[@]}"}" \
    "${tmpfs_args[@]+"${tmpfs_args[@]}"}" \
    "${ports_args[@]+"${ports_args[@]}"}" \
    "${mounts_args[@]+"${mounts_args[@]}"}" \
    "$target_image"
  echo "[Upgrade] Container '$CONTAINER_NAME' successfully upgraded and started."
else
  # Recreate in a stopped state
  "$ENGINE" create \
    --name "$CONTAINER_NAME" \
    "${readonly_args[@]+"${readonly_args[@]}"}" \
    "${tmpfs_args[@]+"${tmpfs_args[@]}"}" \
    "${ports_args[@]+"${ports_args[@]}"}" \
    "${mounts_args[@]+"${mounts_args[@]}"}" \
    "$target_image"
  echo "[Upgrade] Container '$CONTAINER_NAME' successfully upgraded in stopped state."
fi
