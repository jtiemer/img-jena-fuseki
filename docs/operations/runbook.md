# Runbook

Step-by-step procedures for local development, testing, and data management.

## Local Setup

### 1. Validate scaffolding

Checks file presence, shell syntax, and (optionally) `shellcheck`/`shfmt`:

```bash
bash tests/smoke_test.sh
```

### 2. Build image

```bash
bash scripts/build-image.sh
```

### 3. Create and start dev container

```bash
bash scripts/manage-container.sh create dev
```

### 4. Verify health

```bash
curl -fsS http://localhost:3030/$/ping
```

Expected: ISO 8601 timestamp.

### 5. Query initial state

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=SELECT (COUNT(?s) as ?count) WHERE { ?s ?p ?o }"
```

Expected: `count = 0`.

### 6. Insert a triple

```bash
curl -fsS -u admin:change-me -X POST \
  "http://localhost:3030/default/update" \
  --data-urlencode "update=PREFIX ex: <http://example.org/> INSERT DATA { ex:item1 ex:name \"Test Item\" . }"
```

### 7. Query the triple

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=PREFIX ex: <http://example.org/> SELECT ?name WHERE { ?s ex:name ?name }"
```

Expected: JSON containing `Test Item`.

### 8. Fulltext search

```bash
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=PREFIX text: <http://jena.apache.org/text#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT ?s ?label WHERE { (?s ?score ?label) text:query (rdfs:label \"test\") . }"
```

### 9. Verify persistence

Restart and re-query:

```bash
bash scripts/manage-container.sh stop dev
bash scripts/manage-container.sh start dev
# wait for health check
curl -fsS -u admin:change-me \
  -H "Accept: application/sparql-results+json" \
  -G "http://localhost:3030/default/query" \
  --data-urlencode "query=PREFIX ex: <http://example.org/> SELECT ?name WHERE { ?s ex:name ?name }"
```

Expected: `Test Item` still returned.

---

## Integration Tests

Run the full integration test suite (builds image, creates test container, runs all checks, cleans up):

```bash
FOR_TESTS=true bash scripts/build-image.sh
bash tests/integration_test.sh
```

Test coverage: SPARQL query/update, named-graph isolation, Lucene search, GSP read/write, SHACL validation, restart
persistence, Jena CLI offline query, config mount override.

---

## Data Management

### Backup

```bash
bash pipelines/backup.sh
```

Output: `.local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz`.

For transaction-safe backups, stop the container and use `tdb2.tdbbackup` (see
[operations guide](operations.md#transaction-safe-backup-cli-tools)).

### Restore

```bash
bash scripts/manage-container.sh stop dev
bash pipelines/restore.sh .local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz
bash scripts/manage-container.sh start dev
```

---

## Cleanup

Remove container and data volume:

```bash
bash scripts/manage-container.sh delete dev
docker volume rm fuseki-dev-data
```

---

## Troubleshooting

### Port 3030 in use

The port auto-resolves. Override manually:

```bash
FUSEKI_PORT=3031 bash scripts/manage-container.sh create dev
```

Or find the current listener:

```bash
docker ps | grep 3030
```

### Lucene indexing error on startup

Entrypoint checks for `text:TextDataset` in `config.ttl`. To run without fulltext:

```bash
REQUIRE_LUCENE=false bash scripts/manage-container.sh create dev
```

### Invalid credentials

Inspect the mounted Shiro config:

```bash
docker exec fuseki-dev cat /fuseki/config/shiro.ini
```

### Offline database query

Query TDB2 directly via CLI (server must be stopped):

```bash
docker exec -it fuseki-dev tdb2.tdbquery \
  --loc=/fuseki/data/default "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
```

### Container permission errors

On Linux, `mktemp -d` creates directories with mode 700 owned by the host UID. If mounting into the container as a
config override, ensure the directory is readable by UID 100:

```bash
chmod 755 /path/to/config/dir
chmod 644 /path/to/config/dir/*
```
