#!/usr/bin/env bash
# Tags HEAD with v<version> from .cz.toml, provided the version increased
# since the previous reachable v* tag. Intended for CI: run on push to
# dev/main, after a PR has landed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

current_version=$(grep -E '^version = ' "$ROOT_DIR/.cz.toml" | sed -E 's/^version = "(.*)"$/\1/')
if [[ -z "$current_version" ]]; then
  echo "ERROR: could not read version from .cz.toml" >&2
  exit 1
fi

previous_tag=$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || true)
previous_version="${previous_tag#v}"

if [[ -n "$previous_version" ]]; then
  highest=$(printf '%s\n%s\n' "$current_version" "$previous_version" | sort -V | tail -n1)
  if [[ "$current_version" == "$previous_version" ]]; then
    echo "ERROR: version was not bumped (still ${current_version}); refusing to create a duplicate tag." >&2
    exit 1
  fi
  if [[ "$highest" != "$current_version" ]]; then
    echo "ERROR: version went backwards (${previous_version} -> ${current_version})." >&2
    exit 1
  fi
fi

tag="v${current_version}"
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag ${tag} already exists; skipping."
else
  git tag "$tag"
  git push origin "$tag"
  echo "Created and pushed tag ${tag}."
fi
