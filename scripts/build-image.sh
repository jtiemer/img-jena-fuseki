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
IS_RELEASE="${RELEASE_BUILD:-false}"

for arg in "$@"; do
  case "$arg" in
  --release | -r)
    IS_RELEASE="true"
    ;;
  *) ;;
  esac
done
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

FOR_TESTS="${FOR_TESTS:-false}"

if [[ "$IMAGE_TAG" == "dev" ]]; then
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
    IMAGE_TAG="${VERSION}-test"
  elif [[ "$IS_RELEASE" == "true" ]]; then
    IMAGE_TAG="${VERSION}"
  else
    IMAGE_TAG="${VERSION}-${COMMIT_SHA}"
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
