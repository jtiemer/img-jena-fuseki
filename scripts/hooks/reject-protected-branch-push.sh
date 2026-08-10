#!/usr/bin/env bash
# pre-push hook: rejects pushes made while checked out on a protected branch
# (dev, main). The only valid path onto these branches is a merged pull
# request. Checking the local branch name (not git's push refspec, which
# pre-commit does not reliably forward to hook scripts) is what's actually
# enforceable here.
set -euo pipefail

branch="$(git rev-parse --abbrev-ref HEAD)"
case "$branch" in
dev | main)
  echo "ERROR: direct push from local branch '${branch}' is prohibited." >&2
  echo "Open a pull request instead (see CONTRIBUTING.md)." >&2
  exit 1
  ;;
esac
exit 0
