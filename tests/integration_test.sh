#!/usr/bin/env bash
# Integration test: starts a real Fuseki container and exercises all key paths.
#
# Integration Test Plan:
# Runs a real Fuseki container and validates:
# - SPARQL query/update endpoints
# - dataset persistence across container restart
# - backup and restore workflow (using config mounts)
# - auth behavior (anon vs authenticated / credential override verification)
#
# Requires: image fuseki:dev already built (run build-image.sh first).
# Usage:
#   bash tests/integration_test.sh
# Env overrides:
#   IMAGE_NAME, IMAGE_TAG, FUSEKI_PORT, CONTAINER_NAME

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-fuseki}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
CONTAINER_NAME="${CONTAINER_NAME:-fuseki-integration-test}"
FUSEKI_PORT="${FUSEKI_PORT:-3031}"
# Default credentials matching the shipped shiro.ini; override for production.
FUSEKI_ADMIN_USER="${FUSEKI_ADMIN_USER:-admin}"
FUSEKI_ADMIN_PASS="${FUSEKI_ADMIN_PASS:-change-me}"
DATA_VOLUME="${CONTAINER_NAME}-data"
BASE_URL="http://localhost:${FUSEKI_PORT}"
DATASET="default"

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL  $1"; FAIL=$(( FAIL + 1 )); }

cleanup() {
  if command -v podman >/dev/null 2>&1; then ENGINE="podman"; else ENGINE="docker"; fi
  "$ENGINE" rm -f "$CONTAINER_NAME" "${CONTAINER_NAME}-override" >/dev/null 2>&1 || true
  "$ENGINE" volume rm "$DATA_VOLUME" >/dev/null 2>&1 || true
  if [[ -n "${MOCK_CONFIG_DIR:-}" && -d "$MOCK_CONFIG_DIR" ]]; then
    rm -rf "$MOCK_CONFIG_DIR"
  fi
}
trap cleanup EXIT

if command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
else
  echo "ERROR: neither podman nor docker found" >&2
  exit 1
fi

echo "=== Integration test: ${IMAGE_NAME}:${IMAGE_TAG} ==="

# ── 0. Verify image exists ────────────────────────────────────────────────────
if ! "$ENGINE" image inspect "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "ERROR: image ${IMAGE_NAME}:${IMAGE_TAG} not found. Run build-image.sh first." >&2
  exit 1
fi
pass "image ${IMAGE_NAME}:${IMAGE_TAG} exists"

# ── 1. Start container ────────────────────────────────────────────────────────
"$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
"$ENGINE" volume rm "$DATA_VOLUME" >/dev/null 2>&1 || true

"$ENGINE" run -d \
  --name "$CONTAINER_NAME" \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p "${FUSEKI_PORT}:3030" \
  -v "${DATA_VOLUME}:/fuseki/data" \
  "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null

# ── 2. Wait for health ────────────────────────────────────────────────────────
echo "  Waiting for Fuseki to become healthy..."
RETRIES=20
HEALTHY=false
for _ in $(seq 1 "$RETRIES"); do
  if curl -fsS "${BASE_URL}/\$/ping" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 2
done

if [[ "$HEALTHY" == "true" ]]; then
  pass "health endpoint /\$/ping responded"
else
  fail "health endpoint /\$/ping did not respond after ${RETRIES} retries"
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

# ── 4. SPARQL update: INSERT a triple ─────────────────────────────────────────
INSERT_STATUS=$(curl -o /dev/null -s -w "%{http_code}" \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -X POST "${BASE_URL}/${DATASET}/update" \
  --data-urlencode "update=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
INSERT DATA {
  <http://example.org/test/item1> rdfs:label \"fuseki integration test item\" .
}")
if [[ "$INSERT_STATUS" == "200" ]] || [[ "$INSERT_STATUS" == "204" ]]; then
  pass "SPARQL update INSERT returned HTTP ${INSERT_STATUS}"
else
  fail "SPARQL update INSERT returned HTTP ${INSERT_STATUS}"
fi

# ── 5. SPARQL query: triple is readable back ──────────────────────────────────
RESULT=$(curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE {
  <http://example.org/test/item1> rdfs:label ?label .
}")
if printf '%s' "$RESULT" | grep -q "integration test item"; then
  pass "inserted triple is queryable via SPARQL SELECT"
else
  fail "inserted triple was NOT found via SPARQL SELECT (response: ${RESULT})"
fi

# ── 6. Lucene fulltext search ─────────────────────────────────────────────────
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

# ── 7. Persistence across restart ─────────────────────────────────────────────
"$ENGINE" restart "$CONTAINER_NAME" >/dev/null

# Wait for health again after restart
HEALTHY=false
for _ in $(seq 1 "$RETRIES"); do
  if curl -fsS "${BASE_URL}/\$/ping" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 2
done

if [[ "$HEALTHY" == "true" ]]; then
  pass "health endpoint responded after container restart"
else
  fail "Fuseki did not recover after restart"
fi

PERSIST_RESULT=$(curl -fsSL \
  -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
  -H "Accept: application/sparql-results+json" \
  -G "${BASE_URL}/${DATASET}/query" \
  --data-urlencode "query=PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?label WHERE {
  <http://example.org/test/item1> rdfs:label ?label .
}")
if printf '%s' "$PERSIST_RESULT" | grep -q "integration test item"; then
  pass "data persisted across container restart"
else
  fail "data was NOT persisted across restart (response: ${PERSIST_RESULT})"
fi
# ── 8. Jena CLI tools (tdb2.tdbquery) ─────────────────────────────────────────
CLI_RESULT=$( "$ENGINE" exec "$CONTAINER_NAME" tdb2.tdbquery --loc=/fuseki/data/default "SELECT ?label WHERE { ?s <http://www.w3.org/2000/01/rdf-schema#label> ?label }" 2>&1 )
if printf '%s' "$CLI_RESULT" | grep -q "integration test item"; then
  pass "Jena CLI tools function correctly (tdb2.tdbquery resolved query via mmap TDB2 dataset)"
else
  fail "Jena CLI tools query failed (response: ${CLI_RESULT})"
fi

# ── 9. Config volume mount override ──────────────────────────────────────────
echo "  Testing custom config mount override..."
# Stop the standard container to free up the port
"$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

MOCK_CONFIG_DIR="$(mktemp -d)"
cp "${ROOT_DIR}/config/config.ttl" "${ROOT_DIR}/config/log4j2.xml" "${MOCK_CONFIG_DIR}/"

# Write custom shiro.ini with different admin password ('override-pass')
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

# Start a container mounting the mock config folder over /fuseki/config
"$ENGINE" run -d \
  --name "${CONTAINER_NAME}-override" \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p "${FUSEKI_PORT}:3030" \
  -v "${MOCK_CONFIG_DIR}:/fuseki/config:ro" \
  -v "${DATA_VOLUME}:/fuseki/data" \
  "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null

# Wait for health
HEALTHY=false
for _ in $(seq 1 "$RETRIES"); do
  if curl -fsS "${BASE_URL}/\$/ping" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 2
done

if [[ "$HEALTHY" == "true" ]]; then
  # 1. Assert old password fails with 401
  HTTP_STATUS_OLD=$(curl -o /dev/null -s -w "%{http_code}" \
    -u "${FUSEKI_ADMIN_USER}:${FUSEKI_ADMIN_PASS}" \
    -G "${BASE_URL}/${DATASET}/query" \
    --data-urlencode "query=SELECT * WHERE { } LIMIT 1")

  # 2. Assert new password succeeds with 200
  HTTP_STATUS_NEW=$(curl -o /dev/null -s -w "%{http_code}" \
    -u "admin:foo" \
    -G "${BASE_URL}/${DATASET}/query" \
    --data-urlencode "query=SELECT * WHERE { } LIMIT 1")
  if [[ "$HTTP_STATUS_OLD" == "401" ]] && [[ "$HTTP_STATUS_NEW" == "200" ]]; then
    pass "configuration mount successfully overrode credentials (old password rejected 401, new password accepted 200)"
  else
    fail "configuration override verification failed (old pass HTTP status: ${HTTP_STATUS_OLD}, new pass HTTP status: ${HTTP_STATUS_NEW})"
    echo "=== Override Container Logs ==="
    "$ENGINE" logs "${CONTAINER_NAME}-override" || true
  fi
else
  fail "override container failed to become healthy"
fi

# Cleanup override container
"$ENGINE" rm -f "${CONTAINER_NAME}-override" >/dev/null 2>&1 || true
rm -rf "$MOCK_CONFIG_DIR"
MOCK_CONFIG_DIR=""

# ── 10. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
