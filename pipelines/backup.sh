#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_DIR="$ROOT_DIR"

FUSEKI_DATA_DIR="${FUSEKI_DATA_DIR:-$DB_DIR/.local/fuseki-data}"
BACKUP_DIR="${BACKUP_DIR:-$DB_DIR/.local/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="${BACKUP_DIR}/fuseki-data-${STAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

if [[ ! -d "$FUSEKI_DATA_DIR" ]]; then
  echo "ERROR: data directory not found: $FUSEKI_DATA_DIR" >&2
  exit 1
fi

tar -czf "$OUT_FILE" -C "$FUSEKI_DATA_DIR" .

echo "Backup written: $OUT_FILE"
