# Changelog

Changes are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-10

### Added

- Custom minimal JRE via `jlink` and `jdeps` in a multi-stage build. Analyzes Fuseki/Jena JAR dependencies, assembles a
  stripped-down JRE, and copies it into a minimal `alpine:3.20` runtime base. Reduces image size from ~294 MB to ~167 MB.
- Pruning of Windows scripts (`*.bat`, `*.cmd`) and unused binaries in the builder stage.
- Auto-pruning of untagged images at the end of integration test cleanup (`prune-images.sh`).
- `workflow_dispatch` trigger in CI pipeline for manual runs.
- GitHub Actions pre-commit environment caching (`actions/cache@v4` on `~/.cache/pre-commit`).
- `PCT_TFPATH=tofu` environment variable in CI for OpenTofu-based `terraform_fmt`.
- Dependabot configuration for GitHub Actions, Dockerfile base images, and Terraform providers.
- Trivy container image vulnerability scanning (`trivy-action`) in CI.
- Trivy IaC config scan as a local pre-commit hook (replaces `tfsec`).
- Dynamic shell script collection in `smoke_test.sh`: auto-discovers and validates all `.sh` files via `bash -n`,
  `shellcheck`, and `shfmt` when available.

### Changed

- Base builder image changed from `eclipse-temurin:21-jre-alpine` to `eclipse-temurin:21-jdk-alpine` (required for
  `jdeps`/`jlink`).
- Runtime base image changed from `eclipse-temurin:21-jre-alpine` to `alpine:3.20` (custom JRE replaces the full
  Temurin distribution).
- Retired `tfsec` pre-commit hook in favor of `trivy config`.
- CI `test-gate` job now accepts `pull_request` and `workflow_dispatch` events.

### Fixed

- Alpine OS packages upgraded (`apk upgrade --no-cache`) in both Dockerfile stages to patch CVEs.
- `chmod 755` on `mktemp`-created config directories in `integration_test.sh` to fix non-root container permission
  failures on Linux runners.
- Restored missing `uses: actions/checkout@v4` in CI checkout step.

## [0.0.7] - 2026-08-10

### Added

- `ENGINE: docker` environment variable in CI to ensure Trivy and Docker integrate without ambiguity.
- Explicit `opentofu/setup-opentofu@v1` step in CI for `terraform_fmt` hook.
- Hadolint and Trivy installed as CI tooling (previously relied on pre-commit alone).

### Fixed

- Alpine base packages upgraded in Dockerfile to patch OS-level CVEs.

## [0.0.6] - 2026-08-10

### Added

- Concurrent test container lifecycle in `manage-container.sh`: every `create test` gets a unique hash suffix, tracked
  in `.manage-container-test.state` (tab-delimited, one entry per instance).
- Zombie sweeping: every invocation scans the engine for untracked test containers/volumes and deletes them.
- `TEST_HASH` environment variable for callers to target a specific test instance.
- Deterministic volume naming (`${CONTAINER_NAME}-${SUFFIX}-data[-<hash>]`).
- `FOR_TESTS=true` flag in `build-image.sh` to force `-test` image tags for integration testing.
- Port auto-resolution: `manage-container.sh` increments past occupied ports.

## [0.0.5] - 2026-08-09

### Added

- PR source-branch validation job in CI: PRs into `dev` must originate from a conventional branch prefix; PRs into
  `main` must come from `dev` or a `fix/`/`bugfix/` branch.
- Pre-push hooks: `reject-protected-branch-push.sh` blocks direct pushes to `dev`/`main`;
  `enforce-version-bump.sh` requires a version increment before merging.

### Changed

- Dropped CI auto-bump; version bumps are now manual via `cz bump` with pre-push enforcement.

## [0.0.4] - 2026-08-09

### Added

- `scripts/prune-images.sh`: untags `dev-custom` and removes dangling images from repeated local builds.

### Changed

- Consolidated `run-local.sh` and `upgrade-container.sh` into `scripts/manage-container.sh` with
  `<create|start|stop|delete|upgrade> <dev|test>` subcommands.
- `build-image.sh` defaults `create`/`upgrade` tags by suffix (`*-dev` or `*-test`) and restricts `upgrade` to dev
  containers only.

## [0.0.3] - 2026-08-09

### Added

- Apache Jena CLI tools (`tdb2.tdbloader`, `tdb2.tdbquery`, `tdb2.tdbcompact`, `tdb2.tdbbackup`, etc.) bundled in
  `/fuseki/app/jena-cli` with `JENA_HOME` and `PATH` configured.
- `JENA_CLI_TOOLS_VERSION` build argument (defaults to `FUSEKI_VERSION`).
- Integration test case for `tdb2.tdbquery` offline verification.

## [0.0.2] - 2026-08-09

### Added

- `upgrade-container.sh` script to upgrade existing dev containers to the latest image tag while preserving volumes,
  ports, and running state.
- Smoke test updated to validate new scripts.

### Fixed

- Commitizen step in GitHub Actions workflow.

## [0.0.1] - 2026-08-08

### Added

- Multi-stage Docker build (`eclipse-temurin:21-jre-alpine`) running Apache Jena Fuseki as non-privileged user `fuseki`
  (UID 100, GID 101).
- Read-only root filesystem support with `tmpfs` mounts for `/fuseki/run` and `/tmp`.
- Persistent TDB2 storage via named volumes (`/fuseki/data`).
- Embedded Lucene fulltext search on `rdfs:label`, `skos:prefLabel`, `skos:altLabel`, `rdfs:comment`,
  `skos:definition`.
- HTTP Basic authentication via Apache Shiro with SHA-256 hashed credentials.
- Console and structured JSON logging via log4j2.
- `build-image.sh` with dynamic Fuseki version resolution from Maven Central.
- `.env.build` / `.env.run` environment configuration files.
- Pre-commit hooks: `hadolint`, `shellcheck`, `shfmt`, `gitleaks`, branch naming check, Commitizen conventional
  commits.
- GitHub Actions CI pipeline with linting, smoke tests, and integration tests on PRs; release tagging on merge.
- Smoke test (`smoke_test.sh`) and integration test (`integration_test.sh`).
- Backup (`pipelines/backup.sh`) and restore (`pipelines/restore.sh`) scripts.
- Terraform scaffold for Azure Resource Group.
- Documentation: architecture overview, development guide, operations guide, runbook, roadmap.

## v0.1.8 (2026-08-10)

## v0.1.7 (2026-08-10)

## v0.1.6 (2026-08-10)

## v0.1.5 (2026-08-10)

## v0.1.4 (2026-08-10)

## v0.1.3 (2026-08-10)

## v0.1.2 (2026-08-10)

## v0.1.1 (2026-08-10)

## v0.0.7 (2026-08-10)

### Feat

- **build**: minify container image using custom jlink JRE
- **test**: auto-prune untagged images at end of integration test cleanup

### Fix

- **ci**: restore actions/checkout@v4 in checkout step
- **ci**: use PCT_TFPATH=tofu env var for pre-commit-terraform
- **test**: chmod 755 mktemp config directory for non-root container permissions
- **security**: upgrade Alpine base packages in Dockerfile to patch CVEs

### Refactor

- **ci**: refine pre-commit hooks, add GHA caching, pass --tf-path=tofu, and enhance smoke_test

## v0.0.6 (2026-08-10)

### Feat

- **scripts**: concurrent test container lifecycle, zombie sweeping, and tag resolution

## v0.0.5 (2026-08-09)

## v0.0.4 (2026-08-09)

### Feat

- **scripts**: default create/upgrade tags by suffix, restrict upgrade to dev
- **scripts**: add prune-images.sh to clean up local dev image tags

### Fix

- version 0.0.3 → 0.0.4
- **fix-broken-tag-and-version**: erroneous cz bump reverted. version/tag corrected --> 0.0.4/v0.0.4

### Refactor

- **scripts**: consolidate run-local.sh/upgrade-container.sh into manage-container.sh

## v0.0.3 (2026-08-09)

### Feat

- **image**: add Apache Jena CLI tools to Dockerfile stage 1 and 2
- **build**: add JENA_CLI_TOOLS_VERSION config and build argument

## v0.0.2 (2026-08-09)

## v0.0.1 (2026-08-09)

### Feat

- initial commit of the hardened Apache Jena/Fuseki service image
