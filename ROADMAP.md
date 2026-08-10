# Database Service Roadmap

Current and future feature status of the image.

## Feature Status Summary

| Category            | Feature                         | Status  | Priority |
|---------------------|---------------------------------|---------|----------|
| **Build & Runtime** | Dynamic Fuseki version          | DONE    | -        |
|                     | Container health checks         | DONE    | -        |
|                     | Named volume persistence        | DONE    | -        |
|                     | Dev/test container lifecycle    | DONE    | -        |
|                     | Stale local image pruning       | DONE    | -        |
|                     | Minified custom JRE (`jlink`)    | DONE    | -        |
|                     | Env vars & configuration        | PARTIAL | -        |
| **RDF & Search**    | TDB2 + Lucene indexing          | DONE    | -        |
|                     | Multi-dataset support           | PARTIAL | -        |
|                     | Bulk loader & offline CLI tools | DONE    | -        |
|                     | Graph-level ACLs                | TODO    | MAYBE    |
| **Auth & Security** | HTTP Basic + Shiro              | DONE    | -        |
|                     | Hashed passwords                | DONE    | -        |
|                     | Azure AD integration            | TODO    | HIGH     |
|                     | TLS/HTTPS enforcement           | TODO    | HIGH     |
| **Operations**      | Backup/restore scripts          | PARTIAL | -        |
|                     | Transaction-safe backups        | TODO    | HIGH     |
|                     | ADLS backup integration         | PARTIAL | HIGH     |
|                     | Backup lifecycle/retention      | TODO    | MEDIUM   |
| **Testing**         | Smoke check                     | DONE    | -        |
|                     | Integration check               | DONE    | -        |
|                     | Performance benchmarks          | TODO    | LOW      |
|                     | Security & CVE scanning         | PARTIAL | LOW      |
|                     | SBOM generation & publishing    | TODO    | LOW      |
|                     | End-to-end / stress test        | TODO    | LOW      |
| **Infrastructure**  | Terraform scaffolding           | PARTIAL | LOW      |
|                     | CI/CD pipeline (GitHub Actions) | PARTIAL | HIGH     |
|                     | HA / failover cluster           | TODO    | LOW      |
| **Docs**            | Developer & Arch Guides         | DONE    | -        |
|                     | README.md                       | DONE    | -        |
|                     | Runbook                         | DONE    | -        |
|                     | Operations guide                | PARTIAL | TODO     |
|                     | Architecture Decisions (ADRs)   | TODO    | TODO     |
|                     | Troubleshooting guide           | TODO    | TODO     |

---

## Detailed Feature Status

### Container Build & Runtime

#### DONE: Dynamic image build with latest Fuseki version

- `scripts/build-image.sh` auto-resolves and builds the latest stable Fuseki release.
- Uses pinned Eclipse Temurin 21 JRE Alpine base image.
- Supports `certs/enterprise-certs.crt` for corporate proxy interception.

#### DONE: Container startup with health checks

- Entrypoint configures transient `/fuseki/run` and launches Fuseki on port 3030.
- Unauthenticated health check endpoint `/$/ping` returns an ISO 8601 timestamp.
- Enforces presence of fulltext Lucene search configuration on startup (`REQUIRE_LUCENE=true`).

#### DONE: Named volume persistence

- `scripts/manage-container.sh create dev` mounts persistent data to a deterministically-named volume
  (`${CONTAINER_NAME}-dev-data`).
- Avoids host bind-mount filesystem sharing complications across platforms.

#### DONE: Dev/test container lifecycle management

- `scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test>` names containers exclusively as
  `${CONTAINER_NAME}-dev` or `${CONTAINER_NAME}-test`.
- `dev` mounts a persistent, deterministic data volume (`${CONTAINER_NAME}-dev-data`) and a read-only
  `FUSEKI_CONFIG_VOLUME` from `.env.run`; `test` mounts a dedicated, disposable data volume per instance
  (`${CONTAINER_NAME}-test-data-<hash>`), supporting several concurrent instances tracked in
  `.manage-container-test.state`.
- `upgrade` recreates the target container against `<image>:latest`, preserving its prior running/stopped state.

#### DONE: Stale local image pruning

- `scripts/prune-images.sh` untags the `dev-custom` build tag and removes dangling (untagged) images left behind by
  repeated local builds.

#### DONE: Minified custom JRE and image optimization (`jlink` + `jdeps`)

- Uses multi-stage build with `eclipse-temurin:21-jdk-alpine` to analyze dependencies via `jdeps` and assemble a minimal custom JRE via `jlink`.
- Prunes Windows scripts (`*.bat`, `*.cmd`), sample files, and unnecessary binaries in Stage 1.
- Copies `/custom-jre` into a minimal `alpine:3.20` runtime base image.
- Reduces total container image size from ~294 MB down to ~167 MB (a 43% size reduction) while keeping full Fuseki, Lucene, and Jena CLI tool functionality.

#### PARTIAL: Configuration via environment variables
- **Supported**: Sourcing `.env.run`; configuration variables: `JVM_ARGS`, `LOGGING`, `REQUIRE_LUCENE`,
  `FUSEKI_CONFIG_DIR`, `FUSEKI_DATA`, `FUSEKI_RUN`, `FUSEKI_HOME`, `FUSEKI_BASE`.
- **Gaps**: No template variable expansion in `config.ttl`; Lucene index path is hardcoded inside `config.ttl`.
- **Workaround**: Mount configuration overrides (`config.ttl`, `shiro.ini`, `log4j2.xml`) at runtime using host-to-file
  bindings.

---

### RDF Data & Indexing

#### DONE: TDB2 triple storage with Lucene fulltext search

- Default config uses TDB2 (`/fuseki/data/default`) and Lucene (`/fuseki/data/default-lucene`).
- Fulltext query via `text:query` indexes `rdfs:label`, `skos:prefLabel`, `skos:altLabel` (on field `text`), and
  `rdfs:comment`, `skos:definition` (on field `text_long`).
- Automatic indexing on data updates.

#### PARTIAL: Multi-dataset support

- **Supported**: Assembler configuration (`config.ttl`) allows configuring multiple service blocks.
- **Gaps**: No automation helpers or UI to dynamically add/remove datasets. Backup/restore is performed at volume level,
  not per dataset.

#### TODO: Graph-level access control (Priority: MAYBE)
- **Gaps**: Shiro configuration restricts access at URL/endpoint level, not per-graph.
- **Future**: Investigate custom Shiro filters or Jena access control mechanisms.

#### DONE: Bulk loading & offline CLI tools
- The container bundles the `apache-jena` command-line tools (`tdb2.tdbloader`, `tdb2.xloader`, `tdb2.tdbcompact`,
  `tdb2.tdbdump`, `tdb2.tdbbackup`, `tdb2.tdbquery`) at `/fuseki/app/jena-cli`, with `JENA_HOME` and `PATH` configured.
  Version pinned via `JENA_CLI_TOOLS_VERSION` (defaults to `FUSEKI_VERSION`).

---

### Authentication & Authorization

#### DONE: HTTP Basic auth with SHA-256 password hashing

- Default configuration (`config/shiro.ini`) uses SHA-256 hashes with `Sha256CredentialsMatcher` for authentication.
- URL matching enforces basic authentication (`authcBasic`) on all non-health data endpoints.

#### DONE: Secure password management

- Baseline credentials (`admin`, `reader`) use hashed passwords.
- **Gaps**: No automated credential rotation; no external IDP integration.
- **Mitigation**: Users must mount custom `shiro.ini` files with unique hashes in production.

#### TODO: Azure AD integration (SAML 2.0 / OpenID Connect) (Priority: HIGH)

- **Approach**: Add Shiro SAML/OIDC plugin, configure Redirect URI matching Azure AD metadata, and map AD groups to
  database roles.
- **Prerequisites**: TLS/HTTPS must be enabled first.

#### TODO: TLS/HTTPS enforcement (Priority: HIGH)

- **Gaps**: Currently HTTP only on port 3030; credentials sent base64-encoded.
- **Approach**: Enable TLS listener in entrypoint/Fuseki on port 8443; update health check endpoints. Alternatively,
  terminate TLS at load balancer / proxy.

---

### Operations & Backup

#### DONE: Backup/restore scripts

- `pipelines/backup.sh` creates a tarball of the host data directory (default: `.local/fuseki-data`).
- `pipelines/restore.sh` extracts the tarball into target directory.

#### PARTIAL: ADLS backup integration (Priority: HIGH)

- **Supported**: Host-level execution of CLI uploading backups.
- **Gaps**: Container has no native Azure CLI or ADLS stream capability.
- **Workaround**: Schedule cron/orchestration job outside the container to upload local backup tarballs.

#### TODO: Transaction-safe database backups (Priority: HIGH)

- **Gaps**: `pipelines/backup.sh` currently runs `tar` on a live TDB2 directory on the host. Since TDB2 uses
  memory-mapped files and active write-ahead journals, archiving these files while the JVM is running can capture
  partial writes, leading to corrupted, unrecoverable backup archives.
- **Future**: Refactor backup script to trigger Jena's transactional backup utility (`tdb2.tdbbackup`) or call the
  Fuseki administration API (`POST /$/backup/{dataset}`) to generate consistent, transaction-safe N-Quads dump
  (`.nq.gz`) files.

#### TODO: Backup retention & lifecycle (Priority: MEDIUM)

- **Gaps**: No automatic retention pruning or backup validation.
- **Future**: Implement cleanup script for old backups and retention policy in Terraform.

---

### Testing & Quality

#### DONE: Smoke test

- `tests/smoke_test.sh` validates syntax of shell scripts and checks file structure. Runs in <1 second.

#### DONE: Integration test

- `tests/integration_test.sh` builds image, starts container, verifies query/update endpoints, Lucene search,
  persistence, and credentials override.

#### TODO: Performance benchmarks (Priority: LOW)

- **Gaps**: No baseline latency/ingestion metrics or regression checks.

#### PARTIAL: Security scanning (Priority: LOW)

- **Supported**: Static analysis (`hadolint`, `tfsec`), secret detection (`gitleaks`) via pre-commit and CI gates;
  container image vulnerability scanning (`trivy-action` in GHA and `trivy-config` pre-commit hook).
- **Gaps**: No container image Software Bill of Materials (SBOM) generated or published.

#### TODO: SBOM generation and publishing (Priority: LOW)

- **Gaps**: No Software Bill of Materials (SBOM) is generated during container compilation or published alongside
  releases.
- **Approach**: Integrate Syft/Trivy in GitHub Actions release pipelines to generate CycloneDX or SPDX JSON SBOMs, and
  upload them as release assets or OCI registry attestations via Cosign.

#### TODO: End-to-end test (Priority: LOW)

- **Future**: Stress-test concurrent queries, multiple datasets, and large triple counts.

---

### Infrastructure & Deployment

#### PARTIAL: Terraform scaffolding (Azure)

- **Supported**: Provisions Azure Resource Group.
- **Gaps**: Lacks Container Apps/AKS configurations, network security rules, secret management (Key Vault integration),
  and storage account for backups. The scaffold is currently empty and does not support automated container deployments.

#### PARTIAL: CI/CD pipeline (Priority: HIGH)

- **Supported**: GitHub Actions workflow (`ci.yml`) runs linting, smoke tests, and integration tests on PRs. On merge to
  `dev`, tags dev release and bumps patch version via Commitizen. On merge to `main`, tags release.
- **Gaps**: No image push to container registry (ACR) or automated deployment.

#### TODO: High availability & failover (Priority: LOW)

- **Future**: Jena TDB2 lacks native clustering. Clustering requires single-writer/multi-reader replication or
  commercial triplestore (e.g. GraphDB).

---

### Documentation & Developer Experience

#### DONE: Developer & Architecture Guides

- `docs/architecture/overview.md` and `docs/development/guide.md` detail stack, configurations, git workflows, and CI
  gates.

#### DONE: README.md & Runbook

- Quickstart configurations, local test steps, diagnostic commands, and recovery guides.

#### PARTIAL: Operations guide

- **Gaps**: Lacks Azure AppInsights/KeyVault configuration details and recovery runbooks.

#### TODO: Architecture Decision Records (ADRs) & Troubleshooting Guide

- **Future**: Document design decisions and common runtime failures (OOM, index corruption).
