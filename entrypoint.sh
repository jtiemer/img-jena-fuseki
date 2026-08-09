#!/usr/bin/env sh
set -eu

: "${FUSEKI_CONFIG_DIR:=/fuseki/config}"
: "${FUSEKI_DATA:=/fuseki/data}"
: "${FUSEKI_RUN:=/fuseki/run}"
: "${FUSEKI_HOME:=/fuseki/app}"
: "${REQUIRE_LUCENE:=true}"

FUSEKI_CONFIG="$FUSEKI_CONFIG_DIR/config.ttl"

mkdir -p "$FUSEKI_DATA" "$FUSEKI_RUN"
export FUSEKI_BASE="${FUSEKI_BASE:-$FUSEKI_RUN}"
ln -sf "$FUSEKI_CONFIG_DIR/shiro.ini" "$FUSEKI_BASE/shiro.ini"

if [ "$REQUIRE_LUCENE" = "true" ] && ! grep -q "text:TextDataset" "$FUSEKI_CONFIG"; then
  echo "ERROR: fulltext indexing is required by default. Mount a config with text:TextDataset or set REQUIRE_LUCENE=false." >&2
  exit 1
fi

# Set logging and JVM memory flags so they can be overridden by environment variables.
export LOGGING="${LOGGING:-"-Dlog4j.configurationFile=$FUSEKI_CONFIG_DIR/log4j2.xml"}"
export JVM_ARGS="${JVM_ARGS:-"-Xms512m -Xmx1g"}"

# Keep runtime config paths explicit so mounted files can replace defaults.
# No --localhost flag: Fuseki listens on all interfaces by default when using --config.
exec "$FUSEKI_HOME/fuseki-server" \
  --config="$FUSEKI_CONFIG" \
  --port=3030
