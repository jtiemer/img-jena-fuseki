#!/usr/bin/env bash
# Smoke test (file validation)
# Validates file presence and basic shell syntax of all scripts in the repository.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_DIR="$ROOT_DIR"

required_files=(
  "$DB_DIR/README.md"
  "$DB_DIR/certs/enterprise-certs.crt"
  "$DB_DIR/Dockerfile"
  "$DB_DIR/entrypoint.sh"
  "$DB_DIR/config/config.ttl"
  "$DB_DIR/config/shiro.ini"
  "$DB_DIR/config/log4j2.xml"
  "$DB_DIR/scripts/build-image.sh"
  "$DB_DIR/scripts/run-local.sh"
  "$DB_DIR/pipelines/backup.sh"
  "$DB_DIR/pipelines/restore.sh"
  "$DB_DIR/docs/operations/operations.md"
  "$DB_DIR/docs/operations/runbook.md"
  "$DB_DIR/docs/architecture/overview.md"
  "$DB_DIR/docs/development/guide.md"
  "$DB_DIR/terraform/main.tf"
  "$DB_DIR/terraform/variables.tf"
  "$DB_DIR/terraform/outputs.tf"
  "$DB_DIR/.pre-commit-config.yaml"
  "$DB_DIR/CHANGELOG.md"
  "$DB_DIR/.cz.toml"
  "$DB_DIR/.github/workflows/ci.yml"
  "$DB_DIR/.editorconfig"
  "$DB_DIR/LICENSE"
  "$DB_DIR/CONTRIBUTING.md"
  "$DB_DIR/.github/CODEOWNERS"
)

for f in "${required_files[@]}"; do
  [[ -f "$f" ]] || { echo "Missing required file: $f" >&2; exit 1; }
done

bash -n "$DB_DIR/scripts/build-image.sh"
bash -n "$DB_DIR/scripts/run-local.sh"
bash -n "$DB_DIR/pipelines/backup.sh"
bash -n "$DB_DIR/pipelines/restore.sh"
echo "Verifying Maven Central version resolution path..."
resolved_version=$(curl -fsSL "https://repo1.maven.org/maven2/org/apache/jena/jena-fuseki-server/maven-metadata.xml" \
  | grep -oE '<latest>[^<]+</latest>' \
  | sed -E 's/<latest>([^<]+)<\/latest>/\1/' || true)

if [[ -z "$resolved_version" ]]; then
  echo "ERROR: Maven Central version resolution returned an empty string" >&2
  exit 1
fi

if [[ ! "$resolved_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Resolved version '$resolved_version' does not match semantic version pattern (X.Y.Z)" >&2
  exit 1
fi

echo "Maven Central path verified successfully. Resolved version: $resolved_version"

echo "Scaffold smoke check passed."
