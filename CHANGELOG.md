# Changelog

Changes are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-08-09

### Added

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
- Technical documentation portal containing architectural overview, developer guide, operations guide, runbook, and
  roadmap.
