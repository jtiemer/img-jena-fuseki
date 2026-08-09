#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_DIR="$ROOT_DIR"

FUSEKI_DATA_DIR="${FUSEKI_DATA_DIR:-$DB_DIR/.local/fuseki-data}"
BACKUP_FILE="${1:-}"

if [[ -z "$BACKUP_FILE" ]]; then
  echo "Usage: $0 <backup.tar.gz>" >&2
  exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: backup file not found: $BACKUP_FILE" >&2
  exit 1
fi

mkdir -p "$FUSEKI_DATA_DIR"
tar -xzf "$BACKUP_FILE" -C "$FUSEKI_DATA_DIR"

echo "Restore complete into: $FUSEKI_DATA_DIR"
