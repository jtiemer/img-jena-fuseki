# Architectural Overview

Design, technology stack, and component integration of the containerized Apache Jena/Fuseki service.

## Technology Stack

- **Runtime Base**: `alpine:3.24` with a custom minimal JRE built via `jlink`/`jdeps` from `eclipse-temurin:25-jdk-alpine`.
- **Database Engine**: Apache Jena / Fuseki (TDB2 storage) with bundled Jena CLI tools.
- **Search Engine**: Apache Lucene (integrated via `jena-text`).
- **Security**: Apache Shiro (HTTP Basic authentication, SHA-256 hashed credentials, RBAC).
- **Logging**: log4j2 (Console plain text and ConsoleJson structured JSON output).
- **CI/CD**: GitHub Actions with Dependabot for dependency updates.

## Multi-Stage Build

### Stage 1: Builder (`eclipse-temurin:25-jdk-alpine`)

1. Installs corporate CA certificates from `certs/`.
2. Downloads and extracts Apache Jena Fuseki and Jena CLI tools.
3. Prunes Windows scripts (`*.bat`, `*.cmd`) and unused binaries.
4. Runs `jdeps` against all JARs to identify required JDK modules, then `jlink` to assemble a minimal custom JRE
   (`/custom-jre`) with `--strip-debug`, `--no-man-pages`, `--no-header-files`, `--compress=2`.

### Stage 2: Runtime (`alpine:3.24`)

1. Installs minimal system utilities (`ca-certificates`, `tzdata`, `bash`, `curl`).
2. Creates non-privileged user `fuseki` (UID 100, GID 101).
3. Copies custom JRE, Fuseki binaries, Jena CLI tools, entrypoint, and configuration files.
4. Final image size: ~167 MB.

## Security Model

- **Unprivileged Execution**: Runs as user `fuseki` (UID 100, GID 101). No root access in the runtime container.
- **Read-Only Root Filesystem**: Compatible with `--read-only`. Writable paths:
    - `/fuseki/data` — persistent database volume.
    - `/fuseki/run` — ephemeral `tmpfs` for runtime state and Shiro symlink.
    - `/tmp` — ephemeral `tmpfs` for JVM temporary allocations.
- **Multi-Stage Isolation**: Build tools (`curl`, `tar`, `binutils`, `findutils`, full JDK) remain in Stage 1. The
  runtime image contains only the custom JRE, Fuseki, and Jena CLI binaries.
- **CVE Scanning**: Trivy scans the built image in CI (CRITICAL/HIGH, unfixed ignored). Alpine packages upgraded in
  both stages.

## HTTP API Endpoints

Exposed on port `3030`:

| Endpoint | Auth | Description |
|---|---|---|
| `/<dataset>/query` | Basic Auth | SPARQL 1.1 Query |
| `/<dataset>/update` | Basic Auth | SPARQL 1.1 Update |
| `/<dataset>/shacl` | Basic Auth | SHACL Validation |
| `/<dataset>/data` | Basic Auth | Graph Store Protocol (read/write) |
| `/$/ping` | None | Health check (returns ISO 8601 timestamp) |
| `/$/status` | Basic Auth | Server status and metrics |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `FUSEKI_CONFIG_DIR` | `/fuseki/config` | Directory containing `config.ttl`, `shiro.ini`, `log4j2.xml` |
| `FUSEKI_DATA` | `/fuseki/data` | Persistent database directory |
| `FUSEKI_RUN` | `/fuseki/run` | Transient runtime state directory |
| `FUSEKI_HOME` | `/fuseki/app` | Fuseki binaries directory |
| `FUSEKI_BASE` | Value of `FUSEKI_RUN` | Configuration and runtime base directory |
| `JENA_HOME` | `/fuseki/app/jena-cli` | Apache Jena CLI tools directory |
| `JAVA_HOME` | `/custom-jre` | Custom minimal JRE path |
| `REQUIRE_LUCENE` | `true` | Enforce Lucene index configuration on startup |
| `LOGGING` | `-Dlog4j.configurationFile=...log4j2.xml` | JVM logging flags |
| `JVM_ARGS` | `-Xms512m -Xmx1g` | JVM memory limits |
| `SSL_CERT_FILE` | `/etc/ssl/certs/ca-certificates.crt` | CA certificates trust bundle |

## Configuration Defaults

Defined in `config/config.ttl`:

- Service named `default` with query, update, shacl, and GSP endpoints.
- Lucene fulltext indexing:
    - `rdfs:label`, `skos:prefLabel`, `skos:altLabel` → field `text`.
    - `rdfs:comment`, `skos:definition` → field `text_long`.
- TDB2 data: `/fuseki/data/default`. Lucene index: `/fuseki/data/default-lucene`.
