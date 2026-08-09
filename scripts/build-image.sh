#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_DIR="$ROOT_DIR"

# Load .env.build if it exists
if [ -f "$ROOT_DIR/.env.build" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env.build"
  set +a
fi
IMAGE_NAME="${IMAGE_NAME:-fuseki}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

resolve_latest_fuseki_version() {
  local latest
  latest=$(curl -fsSL "https://repo1.maven.org/maven2/org/apache/jena/jena-fuseki-server/maven-metadata.xml" \
    | grep -oE '<latest>[^<]+</latest>' \
    | sed -E 's/<latest>([^<]+)<\/latest>/\1/' || true)

  if [[ -z "$latest" ]]; then
    local index
    index="$(curl -fsSL "https://downloads.apache.org/jena/binaries/" || true)"
    if [[ -n "$index" ]]; then
      latest="$(printf '%s' "$index" \
        | grep -oE 'apache-jena-fuseki-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
        | sed -E 's/^apache-jena-fuseki-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$/\1/' \
        | sort -V \
        | tail -n1)"
    fi
  fi

  if [[ -z "$latest" ]]; then
    echo "ERROR: unable to resolve latest Fuseki version from Maven or Apache. Set FUSEKI_VERSION explicitly." >&2
    exit 1
  fi

  printf '%s' "$latest"
}

FUSEKI_VERSION="${FUSEKI_VERSION:-$(resolve_latest_fuseki_version)}"
JENA_CLI_TOOLS_VERSION="${JENA_CLI_TOOLS_VERSION:-$FUSEKI_VERSION}"

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker is available" >&2
  exit 1
fi

FOR_TESTS="${FOR_TESTS:-false}"

if [[ "$IMAGE_TAG" == "dev" ]]; then
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  if [[ "$BRANCH" == "detached" ]]; then
    # Fallback to standard CI environment variables in detached HEAD state
    BRANCH="${GITHUB_REF_NAME:-${CI_COMMIT_REF_NAME:-$BRANCH}}"
  fi
  COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  VERSION=""
  if command -v cz >/dev/null 2>&1; then
    VERSION=$(cz version --project 2>/dev/null || true)
  fi
  if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(grep -oE 'version = "[0-9]+\.[0-9]+\.[0-9]+"' "$DB_DIR/.cz.toml" 2>/dev/null | cut -d'"' -f2 || true)
  fi
  if [[ -z "${VERSION:-}" ]]; then
    echo "ERROR: unable to resolve project version from .cz.toml" >&2
    exit 1
  fi

  if [[ "$FOR_TESTS" == "true" ]]; then
    # Built specifically to be exercised by tests/*.sh; branch/tag state is irrelevant.
    IMAGE_TAG="${VERSION}-test"
  else
    # Base version: the exact tag on HEAD if one exists (a just-released commit),
    # otherwise the in-progress version from .cz.toml.
    EXACT_TAG=$(git describe --tags --exact-match --match 'v*' HEAD 2>/dev/null || true)
    BASE_VERSION="${EXACT_TAG#v}"
    [[ -z "$BASE_VERSION" ]] && BASE_VERSION="$VERSION"

    case "$BRANCH" in
    main)
      IMAGE_TAG="$BASE_VERSION"
      ;;
    dev)
      IMAGE_TAG="${BASE_VERSION}-dev"
      ;;
    feat/* | bugfix/* | chore/* | refactor/* | docs/* | style/* | perf/* | test/* | ci/* | build/*)
      # Extract the commitizen prefix (e.g. chore, feat, bugfix) from the branch name
      PREFIX="${BRANCH%%/*}"
      IMAGE_TAG="${BASE_VERSION}-${PREFIX}-${COMMIT_SHA}"
      ;;
    *)
      IMAGE_TAG="${BASE_VERSION}-custom"
      ;;
    esac
  fi
fi

echo "Using container engine: $ENGINE"
echo "Building image: ${IMAGE_NAME}:${IMAGE_TAG}"
"$ENGINE" build \
  --build-arg "FUSEKI_VERSION=${FUSEKI_VERSION}" \
  --build-arg "JENA_CLI_TOOLS_VERSION=${JENA_CLI_TOOLS_VERSION}" \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f "$DB_DIR/Dockerfile" \
  "$DB_DIR"

if [[ "$IMAGE_TAG" != "latest" ]]; then
  echo "Tagging image: ${IMAGE_NAME}:latest"
  "$ENGINE" tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:latest"
fi
