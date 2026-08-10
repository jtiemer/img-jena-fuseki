#!/usr/bin/env bash
# Integration test: exercises a real Fuseki test container end to end.
#
# The container is created and destroyed exclusively via
# scripts/manage-container.sh create/start/stop/delete test - this test never
# runs the container engine directly for the main container, only for the
# throwaway tdb2.tdbquery and config-override probes below, which are
# deliberately outside the standard dev/test lifecycle.
#
# Integration Test Plan:
# - SPARQL query/update, including default-graph vs. named-graph isolation
#   (this dataset has no union default graph: an unqualified query only ever
#   sees the default graph)
# - Lucene fulltext search
# - Graph Store Protocol (GSP) write/read, default and named graph
# - SHACL validation, conforming and violating data
# - dataset persistence across container restart
# - Jena CLI tools: --version smoke check (via `exec`, server running) and a
#   real tdb2.tdbquery read of the data inserted above (server stopped first:
#   TDB2 does not support a second JVM opening a location that is already
#   locked by the running Fuseki server)
# - config volume mount override (auth behavior changes with a custom config)
#
# Requires: an image tagged "<version>-test" already built, e.g.:
#   FOR_TESTS=true bash scripts/build-image.sh
# Usage:
#   bash tests/integration_test.sh [tag]
# Env overrides:
#   IMAGE_NAME, IMAGE_TAG, FUSEKI_PORT, CONTAINER_NAME

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGE="$ROOT_DIR/scripts/manage-container.sh"
TAG_ARG="${1:-}"

IMAGE_NAME="${IMAGE_NAME:-fuseki}"

# CONTAINER_NAME must match whatever manage-container.sh will resolve, so this
# script's curl/exec calls hit the same container it creates.
CONTAINER_NAME="${CONTAINER_NAME:-}"
if [[ -z "$CONTAINER_NAME" && -f "$ROOT_DIR/.env.run" ]]; then
  CONTAINER_NAME=$(grep -E '^CONTAINER_NAME=' "$ROOT_DIR/.env.run" | tail -n1 | cut -d= -f2-)
fi
CONTAINER_NAME="${CONTAINER_NAME:-fuseki}"
export CONTAINER_NAME

# FUSEKI_PORT, if set, is only a starting point: manage-container.sh
# auto-increments past any port already in use (e.g. a running dev
# container), so no fixed port needs to be reserved here.
[[ -n "${FUSEKI_PORT:-}" ]] && export FUSEKI_PORT

# manage-container.sh gives every "test" container/volume a random hash
# suffix; TEST_HASH (captured from `create test`'s own output below) is
# exported so every subsequent start/stop/delete call targets precisely the
# instance this script created, even if other tracked test instances exist
# concurrently (e.g. another agent's test run against the same checkout).
TEST_STATE_FILE="$ROOT_DIR/.manage-container-test.state"

# Default credentials matching the shipped shiro.ini; override for production.
FUSEKI_ADMIN_USER="${FUSEKI_ADMIN_USER:-admin}"
FUSEKI_ADMIN_PASS="${FUSEKI_ADMIN_PASS:-change-me}"
DATASET="default"

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL  $1"; FAIL=$(( FAIL + 1 )); }

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker found" >&2
  exit 1
fi

cleanup() {
  TEST_HASH="${TEST_HASH:-}" bash "$MANAGE" stop test >/dev/null 2>&1 || true
  TEST_HASH="${TEST_HASH:-}" bash "$MANAGE" delete test >/dev/null 2>&1 || true
  "$ENGINE" rm -f "${TEST_CONTAINER_NAME:-}-override" >/dev/null 2>&1 || true
  "$ENGINE" volume rm -f "${TEST_DATA_VOLUME:-}-override" >/dev/null 2>&1 || true
  if [[ -n "${MOCK_CONFIG_DIR:-}" && -d "$MOCK_CONFIG_DIR" ]]; then
    rm -rf "$MOCK_CONFIG_DIR"
  fi
  bash "$ROOT_DIR/scripts/prune-images.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_healthy() {
  local retries=20
  for _ in $(seq 1 "$retries"); do
    if curl -fsS "${BASE_URL}/\$/ping" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "=== Integration test: ${IMAGE_NAME} (tag: ${TAG_ARG:-auto-resolved *-test}) ==="

# ── 1. Create test container ──────────────────────────────────────────────────
if [[ -n "$TAG_ARG" ]]; then
  CREATE_OUTPUT=$(bash "$MANAGE" create test "$TAG_ARG")
else
  CREATE_OUTPUT=$(bash "$MANAGE" create test)
fi
echo "$CREATE_OUTPUT"
# manage-container.sh prints "TEST_HASH=<hash>" on its own stdout, naming
# precisely the instance it just created; export it so every later
# start/stop/delete call in this script targets that same instance even if
# other tracked test instances exist concurrently.
TEST_HASH=$(printf '%s\n' "$CREATE_OUTPUT" | grep '^TEST_HASH=' | cut -d= -f2-)
[[ -n "$TEST_HASH" ]] || { echo "ERROR: 'create test' did not report a TEST_HASH" >&2; exit 1; }
export TEST_HASH
TEST_CONTAINER_NAME="${CONTAINER_NAME}-test-${TEST_HASH}"
TEST_DATA_VOLUME="${CONTAINER_NAME}-test-data-${TEST_HASH}"
FUSEKI_PORT=$(awk -F'\t' -v h="$TEST_HASH" '$1 == h { print $2 }' "$TEST_STATE_FILE")
BASE_URL="http://localhost:${FUSEKI_PORT}"

# Capture the exact image the container was actually started from, so the
# later tdb2.tdbquery/override probes use precisely the same build.
RESOLVED_IMAGE=$("$ENGINE" inspect "$TEST_CONTAINER_NAME" --format '{{.Config.Image}}')

# ── 2. Wait for health ────────────────────────────────────────────────────────
echo "  Waiting for Fuseki to become healthy..."
if wait_healthy; then
  pass "health endpoint /\$/ping responded"
else
  fail "health endpoint /\$/ping did not respond in time"
  exit 1
fi

# ── 3. SPARQL query endpoint responds ─────────────────────────────────────────
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=SELECT * WHERE { } LIMIT 1")
if [[ "$HTTP_STATUS" == "200" ]]; then
  pass "SPARQL query endpoint (${DATASET}/query) returns 200"
else
  fail "SPARQL query endpoint returned HTTP ${HTTP_STATUS}"
fi

# ── 4. SPARQL update: INSERT into the default graph and a named graph ────────
INSERT_STATUS=$(curl -o /dev/null -s -w "%{http_code}" \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X POST "${BASE_URL}/${DATASET}/update" \
  --data-urlencode "update=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
INSERT DATA {
  <http://example.org/test/item1> rdfs:label \"fuseki integration test item\" .
  GRAPH <http://example.org/namedgraph> {
    <http://example.org/test/item2> rdfs:label \"named graph test item\" .
  }
}")
if [[ "$INSERT_STATUS" == "200" ]] || [[ "$INSERT_STATUS" == "204" ]]; then
  pass "SPARQL update INSERT (default + named graph) returned HTTP ${INSERT_STATUS}"
else
  fail "SPARQL update INSERT returned HTTP ${INSERT_STATUS}"
fi

# ── 5. Default graph query sees only the default-graph triple (no union) ─────
DEFAULT_RESULT=$(curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE { ?s rdfs:label ?label }")
if printf '%s' "$DEFAULT_RESULT" | grep -q "fuseki integration test item" \
  && ! printf '%s' "$DEFAULT_RESULT" | grep -q "named graph test item"; then
  pass "unqualified query returns only the default-graph triple (no union default graph)"
else
  fail "unqualified query did not isolate the default graph as expected (response: ${DEFAULT_RESULT})"
fi

# ── 6. Named graph query sees only the named-graph triple ────────────────────
NAMED_RESULT=$(curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE { GRAPH <http://example.org/namedgraph> { ?s rdfs:label ?label } }")
if printf '%s' "$NAMED_RESULT" | grep -q "named graph test item" \
  && ! printf '%s' "$NAMED_RESULT" | grep -q "fuseki integration test item"; then
  pass "GRAPH-qualified query returns exactly the named-graph triple"
else
  fail "named graph query did not isolate the named graph as expected (response: ${NAMED_RESULT})"
fi

# ── 7. Lucene fulltext search ─────────────────────────────────────────────────
TEXT_RESULT=$(curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX text: <http://jena.apache.org/text#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?s ?label WHERE {
  (?s ?score ?label) text:query (rdfs:label \"integration\") .
}")
if printf '%s' "$TEXT_RESULT" | grep -q "integration"; then
  pass "Lucene fulltext text:query returns matching results"
else
  fail "Lucene fulltext text:query did NOT return results (response: ${TEXT_RESULT})"
fi

# ── 8. Graph Store Protocol: write and read the default graph ────────────────
# POST (not PUT) so the earlier default-graph triple (item1) is not replaced.
GSP_DEFAULT_BODY='@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
<http://example.org/test/gsp-default> rdfs:label "gsp default item" .'
GSP_DEFAULT_STATUS=$(printf '%s' "$GSP_DEFAULT_BODY" | curl -o /dev/null -s -w "%{http_code}" \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X POST -H "Content-Type: text/turtle" \
  --data-binary @- \
  "${BASE_URL}/${DATASET}/data?default")
GSP_DEFAULT_GET=$(curl -fsSL -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: text/turtle" "${BASE_URL}/${DATASET}/data?default")
if [[ "$GSP_DEFAULT_STATUS" =~ ^20[0-9]$ ]] && printf '%s' "$GSP_DEFAULT_GET" | grep -q "gsp default item"; then
  pass "GSP write (POST) + read of the default graph round-trips correctly"
else
  fail "GSP default graph round-trip failed (write HTTP ${GSP_DEFAULT_STATUS}, read: ${GSP_DEFAULT_GET})"
fi

# ── 9. Graph Store Protocol: write and read a named graph ────────────────────
GSP_NAMED_BODY='@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
<http://example.org/test/gsp-named> rdfs:label "gsp named item" .'
GSP_NAMED_STATUS=$(printf '%s' "$GSP_NAMED_BODY" | curl -o /dev/null -s -w "%{http_code}" \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X PUT -H "Content-Type: text/turtle" \
  --data-binary @- \
  "${BASE_URL}/${DATASET}/data?graph=http://example.org/gsp-namedgraph")
GSP_NAMED_GET=$(curl -fsSL -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: text/turtle" "${BASE_URL}/${DATASET}/data?graph=http://example.org/gsp-namedgraph")
if [[ "$GSP_NAMED_STATUS" =~ ^20[0-9]$ ]] && printf '%s' "$GSP_NAMED_GET" | grep -q "gsp named item"; then
  pass "GSP write (PUT) + read of a named graph round-trips correctly"
else
  fail "GSP named graph round-trip failed (write HTTP ${GSP_NAMED_STATUS}, read: ${GSP_NAMED_GET})"
fi

# ── 10. SHACL validation: conforming data ─────────────────────────────────────
SHACL_VALID_SHAPE='@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix ex: <http://example.org/test/> .
ex:LabelShape a sh:NodeShape ;
  sh:targetNode ex:item1 ;
  sh:property [ sh:path rdfs:label ; sh:minCount 1 ] .'
SHACL_VALID_RESULT=$(printf '%s' "$SHACL_VALID_SHAPE" | curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X POST -H "Content-Type: text/turtle" \
  --data-binary @- \
  "${BASE_URL}/${DATASET}/shacl?graph=default")
if printf '%s' "$SHACL_VALID_RESULT" | grep -Eq 'sh:conforms[[:space:]]+true'; then
  pass "SHACL validation reports conforms=true for data that satisfies the shape"
else
  fail "SHACL validation did not report conforms=true (response: ${SHACL_VALID_RESULT})"
fi

# ── 11. SHACL validation: violating data ──────────────────────────────────────
SHACL_INVALID_SHAPE='@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix ex: <http://example.org/test/> .
ex:NameShape a sh:NodeShape ;
  sh:targetNode ex:item1 ;
  sh:property [ sh:path foaf:name ; sh:minCount 1 ] .'
SHACL_INVALID_RESULT=$(printf '%s' "$SHACL_INVALID_SHAPE" | curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X POST -H "Content-Type: text/turtle" \
  --data-binary @- \
  "${BASE_URL}/${DATASET}/shacl?graph=default")
if printf '%s' "$SHACL_INVALID_RESULT" | grep -Eq 'sh:conforms[[:space:]]+false' \
  && printf '%s' "$SHACL_INVALID_RESULT" | grep -q "foaf:name"; then
  pass "SHACL validation reports conforms=false with the expected violation for data that fails the shape"
else
  fail "SHACL validation did not report the expected violation (response: ${SHACL_INVALID_RESULT})"
fi

# ── 12. Persistence across restart ────────────────────────────────────────────
bash "$MANAGE" stop test >/dev/null
bash "$MANAGE" start test >/dev/null
if wait_healthy; then
  pass "container became healthy again after restart"
else
  fail "health endpoint did not respond after restart"
fi

PERSIST_DEFAULT=$(curl -fsSL -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE { <http://example.org/test/item1> rdfs:label ?label }")
PERSIST_NAMED=$(curl -fsSL -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE { GRAPH <http://example.org/namedgraph> { <http://example.org/test/item2> rdfs:label ?label } }")
if printf '%s' "$PERSIST_DEFAULT" | grep -q "fuseki integration test item" \
  && printf '%s' "$PERSIST_NAMED" | grep -q "named graph test item"; then
  pass "default and named graph data both survive a container restart"
else
  fail "data did not survive restart (default: ${PERSIST_DEFAULT}, named: ${PERSIST_NAMED})"
fi

# ── 13. Jena CLI tools present (version smoke check, server still running) ───
CLI_RESULT=$("$ENGINE" exec "$TEST_CONTAINER_NAME" tdb2.tdbquery --version 2>&1)
if printf '%s' "$CLI_RESULT" | grep -q "Jena"; then
  pass "Jena CLI tools present in image (tdb2.tdbquery --version)"
else
  fail "tdb2.tdbquery --version did not report a Jena version (output: ${CLI_RESULT})"
fi

# ── 14. tdb2.tdbquery: read the same data directly off the TDB2 store ────────
# TDB2 forbids a second JVM from opening a location the running server already
# holds the lock on, so the server must be stopped first (confirmed: attempting
# this while running throws DBOpEnvException "Failed to get a lock"). The
# volume is intentionally kept (not `delete test`) until after this check.
bash "$MANAGE" stop test >/dev/null

CLI_DEFAULT_RESULT=$("$ENGINE" run --rm --entrypoint tdb2.tdbquery \
  -v "${TEST_DATA_VOLUME}:/fuseki/data" "$RESOLVED_IMAGE" \
  --loc=/fuseki/data/default "SELECT ?label WHERE { <http://example.org/test/item1> <http://www.w3.org/2000/01/rdf-schema#label> ?label }" 2>&1)
if printf '%s' "$CLI_DEFAULT_RESULT" | grep -q "fuseki integration test item"; then
  pass "tdb2.tdbquery reads the default-graph triple directly off the TDB2 store"
else
  fail "tdb2.tdbquery did not read the expected default-graph triple (output: ${CLI_DEFAULT_RESULT})"
fi

CLI_NAMED_RESULT=$("$ENGINE" run --rm --entrypoint tdb2.tdbquery \
  -v "${TEST_DATA_VOLUME}:/fuseki/data" "$RESOLVED_IMAGE" \
  --loc=/fuseki/data/default "SELECT ?label WHERE { GRAPH <http://example.org/namedgraph> { <http://example.org/test/item2> <http://www.w3.org/2000/01/rdf-schema#label> ?label } }" 2>&1)
if printf '%s' "$CLI_NAMED_RESULT" | grep -q "named graph test item"; then
  pass "tdb2.tdbquery reads the named-graph triple directly off the TDB2 store"
else
  fail "tdb2.tdbquery did not read the expected named-graph triple (output: ${CLI_NAMED_RESULT})"
fi

# ── 15. Config volume mount override ──────────────────────────────────────────
# Self-contained: its own volume and mock config, independent of the test
# container above (already stopped, freeing FUSEKI_PORT).
echo "  Testing custom config mount override..."
OVERRIDE_NAME="${TEST_CONTAINER_NAME}-override"
OVERRIDE_VOLUME="${TEST_DATA_VOLUME}-override"
MOCK_CONFIG_DIR="$(mktemp -d)"
chmod 755 "$MOCK_CONFIG_DIR"
cp "${ROOT_DIR}/config/config.ttl" "${ROOT_DIR}/config/log4j2.xml" "${MOCK_CONFIG_DIR}/"
chmod 644 "${MOCK_CONFIG_DIR}"/*

# Custom shiro.ini with a different admin password ('foo').
cat << 'EOF' > "${MOCK_CONFIG_DIR}/shiro.ini"
[main]
sha256Matcher = org.apache.shiro.authc.credential.Sha256CredentialsMatcher
pwRealm = org.apache.shiro.realm.text.IniRealm
pwRealm.credentialsMatcher = $sha256Matcher
pwRealm.resourcePath = file:/fuseki/run/shiro.ini
securityManager.realms = $pwRealm

[users]
admin = 2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae, admin

[roles]
admin = *

[urls]
/$/status = anon
/$/ping = anon
/** = authcBasic
EOF

"$ENGINE" volume create "$OVERRIDE_VOLUME" >/dev/null
"$ENGINE" run -d \
  --name "$OVERRIDE_NAME" \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p "${FUSEKI_PORT}:3030" \
  -v "${MOCK_CONFIG_DIR}:/fuseki/config:ro" \
  -v "${OVERRIDE_VOLUME}:/fuseki/data" \
  "$RESOLVED_IMAGE" >/dev/null

if wait_healthy; then
  HTTP_STATUS_OLD=$(curl -o /dev/null -s -w "%{http_code}" \
    -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
    -G "${BASE_URL}/${DATASET}/query" \
    --data-urlencode "query=SELECT * WHERE { } LIMIT 1")
  HTTP_STATUS_NEW=$(curl -o /dev/null -s -w "%{http_code}" \
    -u "admin:foo" \
    -G "${BASE_URL}/${DATASET}/query" \
    --data-urlencode "query=SELECT * WHERE { } LIMIT 1")
  if [[ "$HTTP_STATUS_OLD" == "401" ]] && [[ "$HTTP_STATUS_NEW" == "200" ]]; then
    pass "configuration mount successfully overrode credentials (old password rejected 401, new password accepted 200)"
  else
    fail "configuration override verification failed (old pass HTTP status: ${HTTP_STATUS_OLD}, new pass HTTP status: ${HTTP_STATUS_NEW})"
    echo "=== Override Container Logs ==="
    "$ENGINE" logs "$OVERRIDE_NAME" || true
  fi
else
  fail "override container failed to become healthy"
fi

"$ENGINE" rm -f "$OVERRIDE_NAME" >/dev/null 2>&1 || true
"$ENGINE" volume rm -f "$OVERRIDE_VOLUME" >/dev/null 2>&1 || true
rm -rf "$MOCK_CONFIG_DIR"
MOCK_CONFIG_DIR=""

# ── 16. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
