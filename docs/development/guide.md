# Development Guide

Guidelines for developing and contributing to this repository.

## Principles

- **Simplicity**: Follow UNIX and container conventions. Keep scripts minimal and composable.
- **Immutability**: Static software in the image. Customization at runtime via env vars or config mounts.
- **Pinning**: Explicitly pin base image tags, software versions, and tool revisions.
- **Security**: Never commit credentials or secrets.
- **Style**: Concise, evidence-based, emoji-free technical writing.

## Project Structure

| Directory | Contents |
|---|---|
| `config/` | Default Fuseki config (`config.ttl`), authentication (`shiro.ini`), logging (`log4j2.xml`) |
| `scripts/` | Build (`build-image.sh`), container lifecycle (`manage-container.sh`), image cleanup (`prune-images.sh`), release tagging (`tag-release.sh`) |
| `scripts/hooks/` | Pre-push hooks: `reject-protected-branch-push.sh`, `enforce-version-bump.sh` |
| `pipelines/` | Data backup (`backup.sh`) and restore (`restore.sh`) |
| `tests/` | Smoke test (`smoke_test.sh`), integration test (`integration_test.sh`) |
| `terraform/` | Azure Resource Group scaffold |
| `docs/` | Architecture overview, development guide, operations guide, runbook |
| `certs/` | Corporate CA certificates for TLS interception proxies |

## Build Image

`scripts/build-image.sh` resolves the latest stable Fuseki version from Maven Central, detects the container engine
(`podman` or `docker`, overridable via `ENGINE`), and tags the image based on branch:

| Branch | Tag Format |
|---|---|
| `main` | `<version>` |
| `dev` | `<version>-dev` |
| `feat/*`, `bugfix/*`, etc. | `<version>-<prefix>-<commit-sha>` |
| Other | `<version>-custom` |

`FOR_TESTS=true` forces a `<version>-test` tag regardless of branch (used by `integration_test.sh`).

Configuration: `.env.build` sets `FUSEKI_VERSION` and `JENA_CLI_TOOLS_VERSION`.

## Run Container

`scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test> [tag]`:

- **`dev`**: persistent, deterministically-named container (`${CONTAINER_NAME}-dev`) and data volume
  (`${CONTAINER_NAME}-dev-data`). Config volume from `FUSEKI_CONFIG_VOLUME` in `.env.run` mounted read-only.
- **`test`**: disposable container with a unique hash suffix. Dedicated data volume per instance. Concurrent instances
  tracked in `.manage-container-test.state`. Every invocation sweeps and deletes untracked test containers/volumes.
- Both use read-only root filesystem with `/fuseki/run` and `/tmp` on `tmpfs`.
- `create`/`upgrade` accept an optional `[tag]`. Without one, `dev` defaults to the newest local `*-dev` tag; `test`
  defaults to `latest`. `IMAGE_TAG` env var overrides both.
- `upgrade` targets dev only (test containers are recreated via `create test`).
- Port auto-resolution: increments past occupied ports.

`scripts/prune-images.sh` untags `dev-custom` and removes dangling images.

Configuration: `.env.run` sets `CONTAINER_NAME`, `FUSEKI_PORT`, `FUSEKI_CONFIG_VOLUME`, `REQUIRE_LUCENE`,
`FUSEKI_ENDPOINT_HEALTH`.

## Testing

- **Smoke test** (`tests/smoke_test.sh`): validates file presence, `bash -n` syntax on all shell scripts, runs
  `shellcheck` and `shfmt` when available, verifies Maven Central version resolution. Runs in <1 second.
- **Integration test** (`tests/integration_test.sh`): spins up a Fuseki test container and exercises SPARQL
  query/update, default-graph vs. named-graph isolation, Lucene fulltext search, Graph Store Protocol, SHACL validation
  (conforming and violating), persistence across restart, Jena CLI `tdb2.tdbquery` offline read, and config volume mount
  override with custom credentials.

## Pre-Commit Hooks

Configured in `.pre-commit-config.yaml`. Install:

```bash
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit install --hook-type pre-push
```

### Blocking hooks

| Hook | Scope |
|---|---|
| `trailing-whitespace`, `end-of-file-fixer`, `check-merge-conflict`, `check-xml`, `check-executables-have-shebangs` | General formatting |
| `branch-check` | Branch naming convention enforcement |
| `shellcheck` | Shell script linting |
| `shfmt` | Shell script formatting (`-i 2 -ci`) |
| `hadolint` | Dockerfile linting |
| `terraform_fmt` | Terraform/OpenTofu formatting |
| `gitleaks` | Secret detection |
| `commitizen` | Conventional Commits message validation (commit-msg stage) |
| `local-trivy-config` | Trivy IaC config scan (when `trivy` is on PATH) |
| `reject-protected-branch-push` | Blocks direct pushes to `dev`/`main` (pre-push stage) |
| `enforce-version-bump` | Requires version bump before merge (pre-push stage) |

### Non-blocking hooks

| Hook | Scope |
|---|---|
| `local-smoke-test` | Runs `smoke_test.sh` (failure does not block commit) |
| `local-integration-test` | Runs `integration_test.sh` (failure does not block commit) |

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ci.yml`):

### Pull requests to `dev`/`main` (and `workflow_dispatch`)

1. Validate merge source branch (conventional prefix required for `dev`; `dev` or `fix/*` for `main`).
2. Install Python, Commitizen, pre-commit, OpenTofu, Hadolint, Trivy.
3. Restore pre-commit environment cache.
4. Run pre-commit checks (`pre-commit run --all-files`).
5. Run smoke tests.
6. Build image.
7. Run Trivy vulnerability scan (CRITICAL/HIGH, fail on findings).
8. Run integration tests.

### Push to `dev`

- Tag release via `scripts/tag-release.sh` (if version was bumped).
- Build dev image (`<version>-dev`).

### Push to `main`

- Tag release via `scripts/tag-release.sh`.
- Build production image (`<version>`).

### Dependency management

Dependabot (`.github/dependabot.yml`) monitors GitHub Actions, Dockerfile base images, and Terraform providers weekly.

## Version Management

- Version tracked in `.cz.toml` (`[tool.commitizen] version`).
- Bump via `cz bump` (Commitizen). Pre-push hook enforces that the version was incremented.
- `scripts/tag-release.sh` creates and pushes a `v<version>` git tag on `dev`/`main` push if the version increased
  since the previous tag.
