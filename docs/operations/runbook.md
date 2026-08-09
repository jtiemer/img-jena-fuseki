# Runbook

Step-by-step procedures for local development, data lifecycle management, and validation.

## Local Setup & Verification

### 1. Validate Scaffolding

Checks file presence and bash script syntax.

```bash
bash tests/smoke_test.sh
```

### 2. Build Container Image

```bash
bash scripts/build-image.sh
```

### 3. Start Container Instance

```bash
bash scripts/run-local.sh
```

### 4. Verify Service Health

```bash
curl -fsS http://localhost:3030/$/ping
```

Expected: ISO 8601 timestamp response.

### 5. Check Initial Database State

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=SELECT (COUNT(?s) as ?count) WHERE { ?s ?p ?o }"
```

Expected: JSON response with triple count equal to `0`.

### 6. Insert Triple

```bash
curl -fsS -u admin:change-me -X POST \
  "http://localhost:3030/default/update" \
  --data-urlencode "update=PREFIX ex: <http://example.org/> INSERT DATA { ex:item1 ex:name \"Test Item\" . }"
```

Expected: HTTP `200` response.

### 7. Retrieve Inserted Triple

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=PREFIX ex: <http://example.org/> SELECT ?name WHERE { ?s ex:name ?name }"
```

Expected: JSON containing `Test Item`.

### 8. Test Fulltext Index Search

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=PREFIX text: <http://jena.apache.org/text#> PREFIX ex: <http://example.org/> SELECT ?item WHERE { (?item ?score ?name) text:query (ex:name 'Test') . }"
```

Expected: JSON containing `http://example.org/item1`.

### 9. Verify Data Persistence

Restart the container and query back the triple:

```bash
docker restart fuseki
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=SELECT ?name WHERE { ?s <http://example.org/name> ?name }"
```

Expected: Triple `Test Item` is returned.

---

## Data Management

### Backup Local host-bound Data

```bash
bash pipelines/backup.sh
```

Expected output: `.local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz`.

### Restore local host-bound Data

```bash
docker stop fuseki
bash pipelines/restore.sh .local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz
docker start fuseki
```

---

## Run Integration Tests

Executes the full test plan inside a temporary container.

```bash
bash tests/integration_test.sh
```

---

## Cleanup

Remove container instance and delete local persistent storage volume:

```bash
docker rm -f fuseki
docker volume rm fuseki-data-dev
```

---

## Troubleshooting

### Port Conflict (Port 3030 already in use)

Identify listener and stop it, or bind to a custom port:

```bash
docker ps | grep 3030
FUSEKI_PORT=3031 bash scripts/run-local.sh
```

### Lucene Indexing Failures

Verify database configuration contains `text:TextDataset`. To run without index, pass `REQUIRE_LUCENE=false` to
environment:

```bash
REQUIRE_LUCENE=false bash scripts/run-local.sh
```

### Invalid Credentials Override

Check target mount file content:

```bash
docker exec fuseki cat /fuseki/config/shiro.ini
```
### Query Dataset Locally (Offline Verification)

To query the database directly from the CLI inside the container (e.g., for offline diagnostics):

```bash
docker exec -it fuseki tdb2.tdbquery --loc=/fuseki/data/default "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
```
