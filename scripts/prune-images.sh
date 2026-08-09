#!/usr/bin/env bash
# Script to prune development image tags and clean up untagged images
set -euo pipefail

# 1. Resolve container engine
if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

IMAGE_NAME="localhost/fuseki"

# 2. Untag "dev-custom" if it exists
echo "[Prune] Untagging 'dev-custom'..."
if "$ENGINE" image inspect "${IMAGE_NAME}:dev-custom" >/dev/null 2>&1; then
  "$ENGINE" rmi "${IMAGE_NAME}:dev-custom"
  echo "[Prune] Untagged ${IMAGE_NAME}:dev-custom successfully."
else
  echo "[Prune] Tag ${IMAGE_NAME}:dev-custom does not exist. Skipping."
fi

# 3. Delete all untagged (dangling) images
echo "[Prune] Cleaning up untagged/dangling images..."
dangling_count=0
while IFS= read -r image_id; do
  if [[ -n "$image_id" ]]; then
    echo "[Prune] Removing dangling image: $image_id"
    "$ENGINE" rmi "$image_id" || true
    dangling_count=$((dangling_count + 1))
  fi
done < <( "$ENGINE" images --filter "dangling=true" --format "{{.Id}}" )

echo "[Prune] Pruning complete. Cleaned up $dangling_count untagged images."
