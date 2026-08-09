# Apache Jena/Fuseki Database Service (docker/podman image)

Build your knowledge graph on an open source database that is _good enough_ for most scenarios. Jena/Fuseki might not be
the fastest or most feature rich setup available, but it provides a database with RDF and SPARQL compliance plus
fulltext search, that supports datasets up to a size larger than most applications will ever need.

This container image packages [Apache Jena/Fuseki](https://jena.apache.org/documentation/fuseki2/index.html) with
embedded Lucene fulltext search, Apache Shiro authentication, and persistent TDB2 storage. It is preconfigured to work
with no further configuration for a simple development setup. Using a volume for data persistence is recommended.

## Default Configuration

The image comes with

* a default TDB2 dataset named `default`
* Lucene full text search enabled on `rdfs:label`, `skos:prefLabel`, and `skos:altLabel` mapped to `text`; and
  `rdfs:comment` as well as `skos:definition` mapped to `text_long`
* HTTP API endpoints
    * _SPARQL 1.1 Query_ on `localhost:3030/default/query`
    * _SPARQL 1.1 Update_ on `localhost:3030/default/update`
    * _SHACL Validation_ on `localhost:3030/default/shacl`
    * _Graph Store HTTP Protocol_ on `localhost:3030/default/data`
* default configuration in `/config/config.ttl`
* default users in `/config/shiro.ini` with sha256-hashed passwords
    * username `admin`, password `change-me`, unrestricted access
    * username `reader`, password `change-me`, access to sparql query only
* default logging in `/config/log4j2.xml`
* basic security
    * default read only filesystem
    * unprivileged user `fuseki` running the jvm process
    * `/fuseki/data/` writable for `fuseki` user
    * `/fuseki/run/` writable for `fuseki` user

## Documentation Index (Portal)

For detailed information on the codebase, please refer to the specific files below:

- **Technology Stack & Security Model**: See [docs/architecture/overview.md](docs/architecture/overview.md)
  (ports, environment variables, multi-stage build structure)
- **Development & Hook Guidelines**: See [docs/development/guide.md](docs/development/guide.md)
  (branch naming conventions, conventional commits, pre-commit setup)
- **Production Operations & Hardening**: See [docs/operations/operations.md](docs/operations/operations.md)
  (running as non-root user, read-only root filesystem configurations, backup/restore designs)
- **Operations Runbook**: See [docs/operations/runbook.md](docs/operations/runbook.md)
  (step-by-step local setup, verification commands, diagnostics, backup execution)
- **Roadmap & Features**: See [ROADMAP.md](ROADMAP.md)
  (feature status and next deployment targets)
- **Version Release History**: See [CHANGELOG.md](CHANGELOG.md) (changelog following Keep a Changelog v1.1.0).

---

## Quickstart

The image is compatible with **Docker** and **Podman**. To get going as quickly as possible, pull the image from the
registry:

```bash
podman pull fake-registry.azurecr.io/fuseki:0.0.1
```

Create a data volume (optional, `fuseki-data` is used as example):

```bash
podman volume create fuseki-data
```

Then adjust the configuration files in `config` to your liking, i.e. `config.ttl`, `shiro.ini`, and `log4j2.xml`.

Mount the volume and the config directory into the container on startup:

```bash
podman run -d \
  --name fuseki \
  --read-only \
  --tmpfs /fuseki/run:mode=1777 \
  --tmpfs /tmp:mode=1777 \
  -p 3030:3030 \
  -v fuseki-data:/fuseki/data \
  -v /path/to/custom/config:/fuseki/config:ro \
  fake-registry.azurecr.io/fuseki:0.0.1
```

**NB:** Replace `podman` with `docker` to select the desired container engine.

## Slightly slower Start

### 1. Build the Image

The build script resolves the latest stable Fuseki release. If one or more corporate proxies like e.g. ZScaler are part
of the equation, their certificate files must be copied into `certs/` as `.crt` files before building.

The build script is compatible with `docker` and `podman`. Run it with:

```bash
bash scripts/build-image.sh
```

### 2. Run Container Locally

Run the image in detached mode on port `3030`:

```bash
bash scripts/manage-container.sh create dev
```

Verify the service is running and healthy:

```bash
curl -fsS http://localhost:3030/$/ping
```

---

## Tests

Verify the repository health with these tests:

**Smoke Checks** (file validation, shell compilation syntax):

```bash
    bash tests/smoke_test.sh
```

**Integration Checks** (SPARQL query/update, fulltext index, restart persistence, config overrides):

 ```bash
    bash tests/integration_test.sh
 ```

## Acknowledgements

Thanks go to the creators and maintainers of
the [SemanticComputing/fuseki-docker](https://github.com/SemanticComputing/fuseki-docker) image. It inspired this
repository and served as my first relevant RDF database when I could not find any other working images of free and open
source triplestore/RDF databases.
