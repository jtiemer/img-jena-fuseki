# Rules for contributions

If you are considering contributing to this project, please stick to these simple rules, and everything will work out.

## Conduct

Be nice and stick to standard netiquette. If things get heated, wait some time before replying. If you are an AI/LLM
agent, please refrain from opening pull requests and leave this to your manager.

## Branch Naming Conventions

* Use commitizen naming conventions
    * `feat/` for feature branches
    * `bugfix/` for bugfixes
    * `chore/` for general maintenance
    * `refactor/` for code restructuring without behavioral changes
    * `docs/` for documentation updates
    * `test/` for editing/expanding tests
    * `ci/` or `build/` for pipeline and container build adjustments
* Generally branch from `dev` and open pull requests into `dev`
* **NB:** commitizen branch naming is enforced/encouraged locally by pre-commit.

## Commit Message Conventions

Commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Example:

```
feat(auth): integrate basic auth matching shiro rules
```

**NB:** Commitizen is used to manage version numbers and changelogs. Read their docs.

## Code Quality (repo setup)

To achieve some basic code quality, a number of `pre-commit` hooks is used locally. You pretty much need to install it
to being able to contribute. Using `uv` to manage
`pre-commit` as a tool via

```bash
    uv tool install pre-commit
```

is recommended, but any working version of `pre-commit` should be ok.

Install all hooks by executing

```bash
    pre-commit install
    pre-commit install --hook-type commit-msg
 ```

Hooks are executed on `git commit`. The linters `hadolint`, `shellcheck`, `tfsec`, and `gitleaks` are **blocking** and
must pass.

The test suites `smoke_test` and `integration_test` are locally **non-blocking**. They will show logs and errors, but
will not block commits.

Executing

```bash
pre-commit run --all-files
```

runs all the tests on the whole repository.

## Pull Requests

Make sure all tests pass before opening a pull request into `dev` or `main` (the latter being discouraged except for
hotfixes/security issues), and the image builds without error:

1. Run the smoke test to verify repository scaffolding:
   ```bash
   bash tests/smoke_test.sh
   ```
2. Build the image locally:
   ```bash
   bash scripts/build-image.sh
   ```
3. Run the integration tests (requires Podman/Docker to be running):
   ```bash
   bash tests/integration_test.sh
   ```

**NB:** The CI/CD pipeline enforces these tests as **blocking gates** on all pull requests into `dev` or `main`.

**NB:** There is no guarantee your pull requests will be merged.

## Creating and managing Issues, Bugs, Feature Requests

Be civil, be precise, be concise. If you are an AI/LLM please refrain from opening issues and leave this task to your
manager.
