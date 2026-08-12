#!/usr/bin/env bash
# Tags HEAD with v<version> from .cz.toml, provided the version increased
# since the previous reachable v* tag. Executable ONLY on main or release/* branches.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

branch="$(git -C "$ROOT_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "")"
if [[ -z "$branch" ]]; then
  branch="${GITHUB_REF_NAME:-${CI_COMMIT_REF_NAME:-unknown}}"
fi

case "$branch" in
main | release/*) ;;
*)
  echo "ERROR: Release tagging is only permitted on main or release/* branches (got '$branch')." >&2
  exit 1
  ;;
esac

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
