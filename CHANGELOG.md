# Changelog

Changes are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## v0.0.7 (2026-08-10)

### Fix

- **security**: upgrade Alpine base packages in Dockerfile to patch CVEs

## v0.0.6 (2026-08-10)

### Feat

- **scripts**: concurrent test container lifecycle, zombie sweeping, and tag resolution

## v0.0.5 (2026-08-09)

## v0.0.4 (2026-08-09)

### Feat

- **scripts**: default create/upgrade tags by suffix, restrict upgrade to dev
- **scripts**: add prune-images.sh to clean up local dev image tags

### Refactor

- **scripts**: consolidate run-local.sh/upgrade-container.sh into manage-container.sh

## v0.0.3 (2026-08-09)

### Feat

- **image**: add Apache Jena CLI tools to Dockerfile stage 1 and 2
- **build**: add JENA_CLI_TOOLS_VERSION config and build argument

## v0.0.2 (2026-08-09)

## v0.0.1 (2026-08-09)

### Feat

- Multi-stage Docker build setup running Apache Jena Fuseki as a non-privileged `fuseki` user.
- Read-only root filesystem compatibility with ephemeral, memory-backed `tmpfs` mounts for `/fuseki/run` and `/tmp`.
- Persistent storage configuration using TDB2 databases and named volumes.
- Embedded Lucene fulltext search indexing configuration.
- Basic HTTP authentication configuration via Apache Shiro using SHA-256 hashed credentials.
- Pre-configured logging (Console and ConsoleJson structured output via `log4j2`).
- Shell scripts for local image building (`build-image.sh`) and local execution (`run-local.sh`).
- Environment configuration via `.env.build` and `.env.run` files.
- Version resolution querying Maven Central metadata with Apache mirror listing scraping fallback.
- Local and CI-enforced pre-commit hooks and Github Actions workflows validating branch naming conventions
  (`efrecon/pre-commit-hook-branch-check`), linting (`hadolint`, `shellcheck`, `tfsec`), secret detection (`gitleaks`),
  syntax (`smoke_test.sh`), configuration security (`trivy config` local hook), container CVE vulnerability scanning
  (`trivy-action` GHA), and integration (`integration_test.sh`).
- Database backup and restore pipelines (`backup.sh`, `restore.sh`).
- Technical documentation portal containing architectural overview, developer guide, operations guide, runbook, and roadmap.
- Automated container upgrade script (`scripts/upgrade-container.sh`) to safely upgrade containers with latest image tags while fully preserving active data volumes, configurations, ports, and states.
- Integrated the full suite of Apache Jena CLI tools (in `/fuseki/app/jena-cli`) to enable offline database backups, compaction, and high-performance bulk loading.
- Added environment configuration variable `JENA_CLI_TOOLS_VERSION` with dynamic version resolution defaulting to `FUSEKI_VERSION` inside the build processes.
