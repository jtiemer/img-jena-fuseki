# Operations Guide

Operating procedures for the containerized Fuseki service.

## Health Checks

Unauthenticated GET to `/$/ping` returns HTTP 200 with an ISO 8601 timestamp. Suitable for liveness/readiness probes.

```bash
curl -fsS http://localhost:3030/$/ping
```

## Logging

All output goes to `stdout` via log4j2. Default level: `INFO`.

- **Plain text** (default): human-readable `PatternLayout`.
- **Structured JSON**: set `JVM_ARGS="-Dlog.appender=ConsoleJson -Xms512m -Xmx1g"` to switch to JSON output.

## Data Persistence

- TDB2 dataset: `/fuseki/data/default`.
- Lucene index: `/fuseki/data/default-lucene`.
- Default dev volume: `${CONTAINER_NAME}-dev-data` (created by `manage-container.sh create dev`).

Inspect volume:

```bash
docker volume inspect fuseki-dev-data
```

## Backup & Restore

### Host-level backup

`pipelines/backup.sh` creates a tarball of the host data directory (default: `.local/fuseki-data`):

```bash
bash pipelines/backup.sh
```

Output: `.local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz`.

**Limitation**: operates on the host filesystem. For named volumes, use container engine export or `tdb2.tdbbackup`.

**Warning**: `tar` on a live TDB2 directory risks capturing partial writes. Stop the container first or use
transaction-safe alternatives below.

### Transaction-safe backup (CLI tools)

The container bundles `tdb2.tdbbackup`. Stop the server first (TDB2 forbids concurrent JVM access):

```bash
bash scripts/manage-container.sh stop dev
docker run --rm -v fuseki-dev-data:/fuseki/data fuseki:latest \
  tdb2.tdbbackup --loc=/fuseki/data/default
```

This generates a `.nq.gz` dump file inside the TDB2 directory.

### Restore

1. Stop the container:
   ```bash
   bash scripts/manage-container.sh stop dev
   ```
2. Extract backup:
   ```bash
   bash pipelines/restore.sh .local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz
   ```
3. Restart:
   ```bash
   bash scripts/manage-container.sh start dev
   ```

## Authentication & Authorization

`config/shiro.ini` defines users, roles, and URL rules:

| Path | Access |
|---|---|
| `/$/status`, `/$/ping` | Anonymous |
| All other paths | HTTP Basic Auth required |

Default users:

| User | Password | Role |
|---|---|---|
| `admin` | `change-me` | Full access |
| `reader` | `change-me` | Query only |

**Production**: mount a custom `shiro.ini` with unique SHA-256 hashed passwords at `/fuseki/config/shiro.ini:ro`.
Generate hashes: `echo -n "password" | sha256sum`.

## Apache Jena CLI Tools

The image includes Jena CLI tools at `JENA_HOME=/fuseki/app/jena-cli` (on `PATH`):
`tdb2.tdbloader`, `tdb2.tdbquery`, `tdb2.tdbcompact`, `tdb2.tdbbackup`, `tdb2.tdbdump`, `tdb2.xloader`.

### Bulk loading

Bypass HTTP endpoints for high-performance loading of large datasets:

```bash
docker exec -it fuseki-dev tdb2.tdbloader --loc=/fuseki/data/default /path/to/dataset.nt
```

### Database compaction

Reclaim disk space after deletions:

```bash
docker exec -it fuseki-dev tdb2.tdbcompact --loc=/fuseki/data/default
```

### Offline query

Query the TDB2 store directly (server must be stopped — TDB2 does not support concurrent JVM access):

```bash
docker run --rm -v fuseki-dev-data:/fuseki/data fuseki:latest \
  tdb2.tdbquery --loc=/fuseki/data/default "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
```

## Hardening

### Non-Privileged User

Runs as `fuseki` (UID 100, GID 101). Kubernetes Pod security context:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
```

### Read-Only Root Filesystem

Compatible with `--read-only`. Required writable paths:

| Path | Mount | Purpose |
|---|---|---|
| `/fuseki/data` | Persistent volume | TDB2 database and Lucene index |
| `/fuseki/run` | `tmpfs` (mode 1777) | Runtime state, Shiro symlink |
| `/tmp` | `tmpfs` (mode 1777) | JVM temporary files |

Example:

```bash
docker run -d \
  --name fuseki \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -v fuseki-dev-data:/fuseki/data \
  -v /path/to/config:/fuseki/config:ro \
  -p 3030:3030 \
  fuseki:latest
```

## Capacity Planning

| Scale | Triples | Disk | Notes |
|---|---|---|---|
| Small | <10K | <100 MB | Default `JVM_ARGS` sufficient |
| Medium | ~1M | ~1 GB | Monitor heap usage |
| Large | >10M | >10 GB | Increase `-Xmx`, consider compaction schedule |

JVM memory defaults: `-Xms512m -Xmx1g` (override via `JVM_ARGS`).
