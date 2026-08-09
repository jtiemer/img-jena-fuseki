#!/usr/bin/env bash
# Enforces that the local .cz.toml version is strictly greater than the
# target branch's current tip version.
#
# Two invocation modes:
#   1. Manual:    scripts/hooks/enforce-version-bump.sh <dev|main>
#   2. pre-push:  invoked with no args. Runs the check against "dev" for any
#      branch other than dev/main itself (pushes made from dev/main are
#      rejected outright by reject-protected-branch-push.sh). Bugfix branches
#      destined for main must be checked manually:
#      scripts/hooks/enforce-version-bump.sh main
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

read_version() {
  grep -E '^version = ' | sed -E 's/^version = "(.*)"$/\1/'
}

check_version() {
  local target="$1" current_version target_version highest

  current_version=$(read_version <"$ROOT_DIR/.cz.toml")
  if ! target_version=$(git show "origin/${target}:.cz.toml" 2>/dev/null | read_version) || [[ -z "$target_version" ]]; then
    echo "WARNING: could not read .cz.toml from origin/${target}; skipping version-bump check." >&2
    return 0
  fi

  highest=$(printf '%s\n%s\n' "$current_version" "$target_version" | sort -V | tail -n1)
  if [[ "$highest" != "$current_version" || "$current_version" == "$target_version" ]]; then
    echo "ERROR: local version (${current_version}) is not greater than ${target}'s current version (${target_version})." >&2
    echo "Run 'cz bump' (past ${target_version}) before merging into ${target}." >&2
    return 1
  fi

  echo "OK: local version (${current_version}) exceeds ${target}'s current version (${target_version})."
}

if [[ $# -ge 1 ]]; then
  check_version "$1"
  exit $?
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
case "$branch" in
dev | main) exit 0 ;; # rejected outright by reject-protected-branch-push.sh
*) check_version "dev" ;;
esac
