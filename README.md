# Apache Jena/Fuseki Database Service (container image)

A container image packaging [Apache Jena/Fuseki](https://jena.apache.org/documentation/fuseki2/index.html) with
embedded Lucene fulltext search, Apache Shiro authentication, Apache Jena CLI tools, and persistent TDB2 storage.
Compatible with Docker and Podman. Preconfigured for immediate development use; production deployments override
configuration via volume mounts.

The image uses a custom minimal JRE built with `jlink`/`jdeps` on an `alpine:3.24` base, reducing the total image size
to ~167 MB while retaining full Fuseki, Lucene, and Jena CLI tool functionality.

## Default Configuration

The image ships with:

* A TDB2 dataset named `default`
* Lucene fulltext search on `rdfs:label`, `skos:prefLabel`, `skos:altLabel` (field `text`) and `rdfs:comment`,
  `skos:definition` (field `text_long`)
* HTTP API endpoints (port 3030, Basic Auth required unless noted):
    * SPARQL 1.1 Query: `/default/query`
    * SPARQL 1.1 Update: `/default/update`
    * SHACL Validation: `/default/shacl`
    * Graph Store Protocol: `/default/data`
    * Health Check: `/$/ping` (unauthenticated)
    * Status: `/$/status`
* Default users (`config/shiro.ini`, SHA-256 hashed passwords):
    * `admin` / `change-me` (unrestricted)
    * `reader` / `change-me` (query only)
* Console and structured JSON logging via log4j2
* Security defaults:
    * Read-only root filesystem (`--read-only`)
    * Non-privileged user `fuseki` (UID 100, GID 101)
    * `/fuseki/data` and `/fuseki/run` writable; `/tmp` on `tmpfs`

## Documentation

| Document                                                        | Contents                                                                     |
|-----------------------------------------------------------------|------------------------------------------------------------------------------|
| [docs/architecture/overview.md](docs/architecture/overview.md)  | Technology stack, security model, environment variables, API endpoints       |
| [docs/development/guide.md](docs/development/guide.md)          | Project structure, build/run workflows, pre-commit hooks, CI pipeline        |
| [docs/operations/operations.md](docs/operations/operations.md)  | Health checks, logging, backup/restore, authentication, hardening, CLI tools |
| [docs/operations/runbook.md](docs/operations/runbook.md)        | Step-by-step local setup, verification commands, troubleshooting             |
| [ROADMAP.md](ROADMAP.md)                                        | Feature status and priorities                                                |
| [CHANGELOG.md](CHANGELOG.md)                                    | Version history                                                              |
| [CONTRIBUTING.md](CONTRIBUTING.md)                              | Contribution rules, branch naming, commit conventions                        |

---

## Quickstart

Pull the image:

```bash
podman pull fake-registry.azurecr.io/fuseki:0.1.0
```

Run with a data volume and read-only root filesystem:

```bash
podman run -d \
  --name fuseki \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p 3030:3030 \
  -v fuseki-data:/fuseki/data \
  -v /path/to/custom/config:/fuseki/config:ro \
  fake-registry.azurecr.io/fuseki:0.1.0
```

Replace `podman` with `docker` as needed.

## Build from Source

The build script auto-resolves the latest stable Fuseki version from Maven Central. Corporate proxy certificates go
into `certs/` as `.crt` files before building.

```bash
bash scripts/build-image.sh
```

## Run Locally

```bash
bash scripts/manage-container.sh create dev
```

Verify:

```bash
curl -fsS http://localhost:3030/$/ping
```

---

## Tests

**Smoke checks** (file presence, shell syntax, optional `shellcheck`/`shfmt`):

```bash
bash tests/smoke_test.sh
```

**Integration checks** (SPARQL query/update, fulltext search, GSP, SHACL validation, persistence, CLI tools, config
override):

```bash
bash tests/integration_test.sh
```

## Acknowledgements

Thanks to the creators and maintainers of
[SemanticComputing/fuseki-docker](https://github.com/SemanticComputing/fuseki-docker). It inspired this repository and
served as my first working RDF database image.
