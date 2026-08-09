# Development Guide

Guidelines for codebase development and contributions.

## Principles

- **Simplicity**: Follow UNIX and container standards. Keep scripts minimal.
- **Immutability**: Maintain static software components within the image. Handle customization at runtime via env vars
  or configuration mounts.
- **Pinning**: Explicitly pin all base image tags and software versions.
- **Security**: Never commit credentials or secrets.
- **Style**: Maintain a professional, evidence-first, emoji-free writing style.

## Project Structure

- `config/`: Default database (`config.ttl`), authentication (`shiro.ini`), and logging (`log4j2.xml`) setups.
- `scripts/`: Local scripts to build (`build-image.sh`), manage dev/test containers (`manage-container.sh`), and prune
  stale local images (`prune-images.sh`).
- `pipelines/`: Scripts to backup and restore databases (`backup.sh`, `restore.sh`).
- `tests/`: Smoke syntax tests (`smoke_test.sh`) and container integration tests (`integration_test.sh`).
- `terraform/`: Scaffolding to deploy resource groups.
- `docs/`: Technical specifications and operation runbooks.

## Workflows

### Build Image

`scripts/build-image.sh` resolves latest stable Fuseki version, detects container engine (`podman` or `docker`), mounts
CA certificates, and tags the image:

- `main` branch: `<version>`
- `dev` branch: `<version>-dev`
- Feature/maintenance branches: `<version>-<prefix>-<commit-sha>` (e.g., `0.0.1-chore-369b880`)

### Run Image

`scripts/manage-container.sh <create|start|stop|delete|upgrade> <dev|test>` manages a container named
`${CONTAINER_NAME}-dev` or `${CONTAINER_NAME}-test` (suffix is mandatory, no other naming is allowed):

- `dev`: mounts persistent data (`FUSEKI_DATA_VOLUME`) and a read-only config directory (`FUSEKI_CONFIG_VOLUME`) from
  `.env.run`.
- `test`: no volumes; runs entirely on defaults baked into the image.
- Both: read-only root filesystem with `/fuseki/run` and `/tmp` mounted on `tmpfs`.
- `upgrade`: recreates the container against `<image>:latest`, preserving its prior running/stopped state.

`scripts/prune-images.sh` untags the `dev-custom` build tag and removes dangling (untagged) images left behind by
repeated local builds.

### Testing

- **Smoke Check (`tests/smoke_test.sh`)**: Validates repository file structure and shell syntax.
- **Integration Check (`tests/integration_test.sh`)**: Starts container, tests health ping, SPARQL Query/Update, Lucene fulltext search, offline query execution via built-in `tdb2.tdbquery` command-line tools, data persistence, and credential override.

## Git Pre-Commit Hooks

Configured via `.pre-commit-config.yaml`.

- **Blocking**: Linters (`hadolint`, `shellcheck`, `tfsec`, `gitleaks`, `shfmt`, and Commitizen conventional commit
  syntax).
- **Non-blocking**: Local smoke and integration tests.
- **Setup**: Install `pre-commit` and execute:
  ```bash
  pre-commit install
  pre-commit install --hook-type commit-msg
  ```

## CI/CD Pipeline

Managed via `.github/workflows/ci.yml`.

- **Pull Requests**: Pull requests targeting `dev` or `main` trigger blocking execution of linters, smoke tests, and
  integration tests.
- **Merge to dev**: Triggers patch version bump and changelog update via Commitizen, pushes Git tag
  `v<version>-<short-sha>`, and builds the dev container.
- **Merge to main**: Creates release Git tag `v<version>` and builds the production container.
