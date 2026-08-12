#!/usr/bin/env bash
# Enforces that the local .cz.toml version is strictly greater than the
# target branch's current tip version when preparing a release.
#
# Version increments are required only for pushes/merges to main or release/* branches.
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
main | release/*) check_version "main" ;;
*) exit 0 ;;
esac
