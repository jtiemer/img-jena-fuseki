# Operations Guide

Operating procedures for the containerized Fuseki service.

## Health Checks

Unauthenticated GET request to `/$/ping` returns HTTP 200 and an ISO 8601 timestamp. Suitable for container runtime and
orchestrator liveness/readiness probes.

```bash
curl -fsS http://localhost:3030/$/ping
```

## Logging

- All logs are directed to `stdout` via `log4j2`. Default log level is `INFO`.
- **JSON Format**: Switch to structured JSON logging by appending `-Dlog.appender=ConsoleJson` to `JVM_ARGS` (e.g.
  `JVM_ARGS="-Dlog.appender=ConsoleJson -Xms512m -Xmx1g"`).

## Data Persistence

- RDF dataset stored in `/fuseki/data/default` (TDB2 layout).
- Fulltext index stored in `/fuseki/data/default-lucene` (Lucene layout).
- Default volume: `fuseki-data-dev`. Monitor disk usage:

```bash
docker volume inspect fuseki-data-dev
```

## Backup & Restore

### Backup

Pruning write traffic is recommended before zipping.

```bash
bash pipelines/backup.sh
```

- Creates a tarball of host data directory (`.local/fuseki-data`) named
  `.local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz`.
- *Note*: Operates on host filesystem. Requires container to run with host bind mount (mapping `.local/fuseki-data` to
  `/fuseki/data`). For named volumes, use native container export commands.

### Restore

1. Stop container:

```bash
podman stop fuseki
```

2. Unpack backup into target host directory:

```bash
bash pipelines/restore.sh .local/backups/fuseki-data-YYYYMMDD-HHMMSS.tar.gz
```

3. Restart container:

```bash
podman start fuseki
```

## Authentication & Authorization

- **Shiro Configuration**: `config/shiro.ini` defines users, roles, and URL rules.
    - `/$/status` and `/$/ping`: Anonymous access (`anon`).
    - All other paths: Basic authentication required (`authcBasic`).
- **Production Overrides**: Mount overrides for config files securely (`config.ttl`, `shiro.ini`, `log4j2.xml`) using
  file-level mounts via environment variables, or mount a directory directly to `/fuseki/config`.

## Apache Jena CLI Tools

The container image includes the full suite of Apache Jena command-line tools (e.g., `tdb2.tdbloader`, `tdb2.tdbcompact`, `tdb2.tdbquery`, `tdb2.tdbbackup`) preconfigured under `JENA_HOME=/fuseki/app/jena-cli` and registered in the system `$PATH`.

### Bulk Loading Datasets
To load large graphs containing millions of triples with high performance, bypass the HTTP endpoints and run `tdb2.tdbloader` directly inside the container against the persistent TDB2 volume:
```bash
podman exec -it -u fuseki fuseki-dev tdb2.tdbloader --loc=/fuseki/data/default /path/to/dataset.nt
```

### Database Compaction
Over time, database deletions and writes leave transaction overhead. Run `tdb2.tdbcompact` to compact the TDB2 storage and reclaim disk space:
```bash
podman exec -it -u fuseki fuseki-dev tdb2.tdbcompact --loc=/fuseki/data/default
```

### Transaction-Safe Offline Backup
Alternatively, to create a consistent, transaction-safe backup dump file natively:
```bash
podman exec -it -u fuseki fuseki-dev tdb2.tdbbackup --loc=/fuseki/data/default
```
This generates a `.nq.gz` backup file inside the container's TDB2 directory.
## Hardening

### Non-Privileged User

Runs under system user `fuseki` (UID 100, GID 101). In Kubernetes, enforce via Pod security context:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
```

### Read-Only Root Filesystem

Compatible with `--read-only` root mounts. Requires the following writable paths:

- `/fuseki/data`: Persistent database volume.
- `/fuseki/run`: Ephemeral, memory-backed `tmpfs` volume (mode 1777).
- `/tmp`: Ephemeral, memory-backed `tmpfs` volume (mode 1777) for JVM temporary allocations.

Example deployment command:

```bash
docker run -d \
  --name fuseki \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -v fuseki-data-dev:/fuseki/data \
  -p 3030:3030 \
  fuseki:latest
```

## Capacity Planning

- **Small Graph**: <10K triples, <100 MB disk.
- **Medium Graph**: ~1M triples, ~1 GB disk.
- **Large Graph**: >10M triples, >10 GB disk.
- **JVM Memory**: Defaults to `-Xms512m -Xmx1g` (configurable via `JVM_ARGS`).
