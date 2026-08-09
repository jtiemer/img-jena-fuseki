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
- `scripts/`: Local scripts to build (`build-image.sh`) and run (`run-local.sh`) the container.
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

`scripts/run-local.sh` runs the container with:

- Named volume persistence (`fuseki-data-dev`).
- Read-only root filesystem with `/fuseki/run` and `/tmp` mounted on `tmpfs`.
- Configuration overrides via env variables (`FUSEKI_CONFIG_FILE`, `FUSEKI_SHIRO_FILE`, `FUSEKI_LOG4J2_FILE`) mounted as
  individual file targets inside `/fuseki/config/`.

### Testing

- **Smoke Check (`tests/smoke_test.sh`)**: Validates repository file structure and shell syntax.
- **Integration Check (`tests/integration_test.sh`)**: Starts container, tests health ping, SPARQL Query/Update, Lucene
  fulltext search, data persistence, and credential override.

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
