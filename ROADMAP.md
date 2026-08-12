# Database Service Roadmap

Current and future feature status of the image.

## Feature Status Summary

| Category            | Feature                          | Status  | Priority |
|---------------------|----------------------------------|---------|----------|
| **Build & Runtime** | Dynamic Fuseki version           | DONE    | -        |
|                     | Minified custom JRE (`jlink`)    | DONE    | -        |
|                     | Container health checks          | DONE    | -        |
|                     | Named volume persistence         | DONE    | -        |
|                     | Dev/test container lifecycle     | DONE    | -        |
|                     | Stale local image pruning        | DONE    | -        |
|                     | Env vars & configuration         | PARTIAL | -        |
| **RDF & Search**    | TDB2 + Lucene indexing           | DONE    | -        |
|                     | Bulk loader & offline CLI tools  | DONE    | -        |
|                     | Multi-dataset support            | PARTIAL | -        |
|                     | Custom Lucene analyzers & predicates | TODO | MEDIUM   |
|                     | Dynamic dataset templating       | TODO    | MEDIUM   |
|                     | Graph-level ACLs                 | TODO    | MAYBE    |
| **Auth & Security** | HTTP Basic + Shiro               | DONE    | -        |
|                     | Hashed passwords                 | DONE    | -        |
|                     | Azure AD integration             | TODO    | HIGH     |
|                     | TLS/HTTPS enforcement            | TODO    | HIGH     |
| **Operations**      | Backup/restore scripts           | PARTIAL | -        |
|                     | Transaction-safe backups         | TODO    | HIGH     |
|                     | ADLS backup integration          | PARTIAL | HIGH     |
|                     | Backup lifecycle/retention       | TODO    | MEDIUM   |
|                     | Prometheus metrics & observability| TODO   | MEDIUM   |
| **Testing**         | Smoke check                      | DONE    | -        |
|                     | Integration check                | DONE    | -        |
|                     | Security & CVE scanning          | DONE    | -        |
|                     | Performance benchmarks           | TODO    | LOW      |
|                     | SBOM generation & publishing     | TODO    | LOW      |
|                     | End-to-end / stress test         | TODO    | LOW      |
|                     | CI/CD pipeline (GitHub Actions)  | DONE    | -        |
|                     | Container registry release push  | TODO    | HIGH     |
|                     | Dependabot dependency updates    | DONE    | -        |
|                     | HA / failover cluster            | TODO    | LOW      |
| **Docs**            | Developer & Arch Guides          | DONE    | -        |
|                     | README.md                        | DONE    | -        |
|                     | Runbook                          | DONE    | -        |
|                     | Operations guide                 | PARTIAL | -        |
|                     | Architecture Decisions (ADRs)    | TODO    | LOW      |

---

## Detailed Feature Status

### Container Build & Runtime

#### DONE: Dynamic image build with latest Fuseki version

- `scripts/build-image.sh` resolves the latest stable Fuseki release from Maven Central (with Apache mirror fallback).
- Supports `certs/enterprise-certs.crt` for corporate TLS interception proxies.

#### DONE: Minified custom JRE (`jlink` + `jdeps`)

- Multi-stage build uses `eclipse-temurin:25-jdk-alpine` to analyze JAR dependencies via `jdeps` and assemble a minimal
  JRE via `jlink` with `--strip-debug`, `--no-man-pages`, `--no-header-files`, and `--compress=2`.
- Prunes Windows scripts (`*.bat`, `*.cmd`) and unused binaries in Stage 1.
- Copies `/custom-jre` into an `alpine:3.24` runtime base.
- Image size: ~167 MB (down from ~294 MB with the full Temurin JRE).

#### DONE: Container startup with health checks

- Entrypoint configures `/fuseki/run`, symlinks `shiro.ini`, and launches Fuseki on port 3030.
- `/$/ping` returns HTTP 200 with an ISO 8601 timestamp (unauthenticated).
- Enforces Lucene fulltext configuration on startup (`REQUIRE_LUCENE=true`).

#### DONE: Named volume persistence

- `manage-container.sh create dev` mounts a deterministically-named volume (`${CONTAINER_NAME}-dev-data`).
- Avoids host bind-mount filesystem sharing issues across platforms.

#### DONE: Dev/test container lifecycle management

- `scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test>`:
    - `dev`: persistent volume, deterministic naming, config volume from `.env.run`.
    - `test`: disposable volume per instance, concurrent instances tracked in `.manage-container-test.state`.
- Zombie sweeping on every invocation: untracked test containers/volumes matching the naming schema are deleted.
- `upgrade` recreates the dev container against a new tag, preserving running/stopped state. Test containers are
  short-lived and recreated via `create test`.

#### DONE: Stale local image pruning

- `scripts/prune-images.sh` untags `dev-custom` and removes dangling images from repeated local builds.

#### PARTIAL: Configuration via environment variables

- **Supported**: `JVM_ARGS`, `LOGGING`, `REQUIRE_LUCENE`, `FUSEKI_CONFIG_DIR`, `FUSEKI_DATA`, `FUSEKI_RUN`,
  `FUSEKI_HOME`, `FUSEKI_BASE`.
- **Gaps**: No template variable expansion in `config.ttl`; Lucene index path is hardcoded.
- **Workaround**: Mount overrides for `config.ttl`, `shiro.ini`, `log4j2.xml` at runtime via `-v`.

---

### RDF Data & Indexing

#### DONE: TDB2 triple storage with Lucene fulltext search

- TDB2 data at `/fuseki/data/default`, Lucene index at `/fuseki/data/default-lucene`.
- Indexed predicates: `rdfs:label`, `skos:prefLabel`, `skos:altLabel` (field `text`); `rdfs:comment`,
  `skos:definition` (field `text_long`).

#### DONE: Bulk loading & offline CLI tools

- Bundles Apache Jena CLI tools (`tdb2.tdbloader`, `tdb2.tdbquery`, `tdb2.tdbcompact`, `tdb2.tdbbackup`, etc.)
  at `/fuseki/app/jena-cli` with `JENA_HOME` and `PATH` configured.
- Version pinned via `JENA_CLI_TOOLS_VERSION` build argument (defaults to `FUSEKI_VERSION`).

#### PARTIAL: Multi-dataset support

- Assembler configuration (`config.ttl`) supports multiple service blocks.
- **Gaps**: No helpers to dynamically add/remove datasets. Backup/restore operates at volume level.

#### TODO: Graph-level access control (Priority: MAYBE)

- Shiro restricts at URL/endpoint level, not per-graph. Would require custom Shiro filters or Jena ACL mechanisms.
- Will probably be provided in the software layer by the goat package.

#### TODO: Custom Lucene analyzers & indexed predicates (Priority: MEDIUM)

- **Gaps**: Predicates (`rdfs:label`, `skos:prefLabel`, `skos:altLabel`, `rdfs:comment`, `skos:definition`) and standard
  Lucene analyzer choices are hardcoded in `config.ttl`. Customizing text indexing for domain ontologies currently
  requires mounting a custom `config.ttl`.
- **Future**: Provide environment variable switches or modular configuration fragments to configure custom analyzers
  (e.g. language-specific stemmers) and predicate mappings.
- **Idea**: build a scaffolding script that guides the user through a set of questions and/or reads their ontology first
  and then builds a working and useful lucene fulltext search configuration from the information obtained.

#### TODO: Dynamic dataset templating (Priority: MEDIUM)

- **Gaps**: `config.ttl` statically defines the `/default` dataset. Dynamic dataset creation or environment-driven
  multi-dataset configuration requires manually replacing the assembler file.
- **Future**: Provide environment-driven configuration templating or CLI helpers to provision additional datasets
  dynamically.
- **Idea**: build a scaffolding script that guides the user through a handful of questions, reads their ontology, and
  then comes up with the information needed to create a new dataset in the dataset from remote … and returns to the
  user all the information needed to connect to the dataset. This could/should be consolidated with the lucene thing.

---

### Authentication & Authorization

#### DONE: HTTP Basic auth with SHA-256 password hashing

- `config/shiro.ini` uses `Sha256CredentialsMatcher`. Basic auth enforced on all non-health endpoints.
- Default credentials: `admin`/`change-me` (full access), `reader`/`change-me` (query only).
- **Production**: mount a custom `shiro.ini` with unique hashes.

#### TODO: Azure AD integration (Priority: HIGH)

- Requires SAML/OIDC Shiro plugin, Redirect URI matching Azure AD metadata, AD group-to-role mapping.
- Prerequisite: TLS/HTTPS.

#### TODO: TLS/HTTPS enforcement (Priority: HIGH)

- Currently HTTP only. Credentials sent base64-encoded.
- Options: TLS listener in Fuseki on port 8443, or TLS termination at load balancer/proxy.

---

### Operations & Backup

#### PARTIAL: Backup/restore scripts

- `pipelines/backup.sh` creates a tarball of the host data directory (`.local/fuseki-data`). [this is crap]
- `pipelines/restore.sh` extracts the tarball. [this too is crap.]
- **Limitation**: operates on host filesystem. For named volumes, use container engine export commands or
  `tdb2.tdbbackup`.
- **Idea**: offer endpoint that takes the necessary info to then trigger a restore routine. It is triggered with a
  snapshot id and commanded to restore the database to the state indicated by the snapshot id (or date). This moves the
  desired snapshot into a blob storage bucket the database can read, tells the database container the URI, lets it
  download the snapshot to its volume. locks the database to stop writes. creates a new snapshot/folder to insert the
  data, insert it, move the db over to the new folder, migrate in-between-writes or something like that, then open for
  write operations again. (This needs some time in the oven still.)
- **Remember**: There are options for stream-compression to compress the data during transmission to avoid using lots
  of space on the volume, even if just transitory.
- push or pull backup? plain triples?
- how to add additional endpoints?

#### PARTIAL: ADLS backup integration (Priority: HIGH)

- Host-level CLI upload works. Container has no native Azure CLI.
- **Workaround**: schedule external cron/orchestration to upload tarballs.

#### TODO: Transaction-safe database backups (Priority: HIGH)

- Current `pipelines/backup.sh` runs `tar` on a live TDB2 directory. TDB2 uses memory-mapped files; archiving during
  writes risks corruption.
- Use `tdb2.tdbbackup` (CLI tool already in the image) or the Fuseki admin API
  (`POST /$/backup/{dataset}`) for consistent `.nq.gz` dumps.

#### TODO: Backup retention & lifecycle (Priority: MEDIUM)

- No automatic retention pruning or backup validation.
- **Idea**: provide a script that can be executed/triggered from remote via an endpoint, that just creates a dump or a
  snapshot of the indicated database, compresses it, pushes it to blob storage, and then deletes the local file again.
- **Problem**: need to investigate what's possible and what's useful and what's the best practice for Apache Jena/TDB2.

#### TODO: Prometheus metrics & observability (Priority: MEDIUM)

- **Gaps**: While `/$/ping` handles basic health checks and `/$/status` provides status metrics via Basic Auth, there is
  no pre-configured Prometheus exporter interface.
- **Future**: Integrate `jena-fuseki-prometheus` module or expose a dedicated Prometheus metrics endpoint for cluster
  monitoring.
- **Idea**: provide switches to offer a prometheus endpoint or to support other means of observability like Dozzle or
  Beszel or both.

---

### Testing & Quality

#### DONE: Smoke test

- `tests/smoke_test.sh` validates file presence, `bash -n` syntax on all repository shell scripts, and runs
  `shellcheck`/`shfmt` when available. Verifies Maven Central version resolution. Runs in <1 second.

#### DONE: Integration test

- `tests/integration_test.sh` exercises a real Fuseki test container: SPARQL query/update, default-graph vs.
  named-graph isolation, Lucene fulltext search, Graph Store Protocol (default and named graph), SHACL validation
  (conforming and violating), persistence across restart, Jena CLI `tdb2.tdbquery` offline read, and config volume mount
  override with custom credentials.

#### DONE: Security & CVE scanning

- Pre-commit: `hadolint` (Dockerfile), `shellcheck` (shell), `gitleaks` (secrets).
- CI: `trivy-action` scans the built container image for CRITICAL/HIGH vulnerabilities.
- Dependabot monitors GitHub Actions and Dockerfile base images.

#### TODO: Performance benchmarks (Priority: LOW)

- No baseline latency/ingestion metrics.

#### TODO: SBOM generation and publishing (Priority: LOW)

- No SBOM generated during build or published with releases.

#### TODO: End-to-end / stress test (Priority: LOW)

- Concurrent queries, multiple datasets, large triple counts.

---

### Infrastructure & Deployment


#### DONE: CI/CD pipeline

- GitHub Actions workflow (`ci.yml`):
    - PRs to `dev`/`main` and `workflow_dispatch`: pre-commit checks, smoke tests, image build, Trivy scan,
      integration tests. Source-branch validation enforces conventional branch prefixes.
    - Push to `dev`: tags release (`tag-release.sh`), builds dev image.
    - Push to `main`: tags release, builds production image.
- Pre-commit environment caching via `actions/cache@v4`.

#### DONE: Dependabot dependency updates

- `.github/dependabot.yml` monitors `github-actions` and `docker` ecosystems weekly.

#### TODO: High availability & failover (Priority: LOW)

- TDB2 lacks native clustering. Requires single-writer/multi-reader replication or a commercial triplestore.

#### TODO: Container registry release image pushing (Priority: HIGH)

- **Gaps**: CI pipeline (`ci.yml`) validates, builds, and tests image artifacts on PRs and merges, but does not push
  compiled container images to a target container registry (e.g. Azure Container Registry / GHCR).
- **Future**: Add registry authentication and `docker push` / `oras` publish steps on release tag creation
  (`main-release` / `dev-release` jobs).
---

### Documentation

#### DONE: Developer & Architecture Guides

- `docs/architecture/overview.md`: stack, security model, environment variables, API endpoints.
- `docs/development/guide.md`: project structure, workflows, hooks, CI.

#### DONE: README.md & Runbook

- Quickstart, local build/run, test commands, troubleshooting.

#### PARTIAL: Operations guide

- **Gaps**: Azure AppInsights/KeyVault configuration, cloud deployment recovery runbooks.

#### TODO: Architecture Decision Records (Priority: LOW)

- Document design decisions, common runtime failures (OOM, index corruption).
