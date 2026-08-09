# Architectural Overview

Design, technology stack, and component integration of the containerized Apache Jena/Fuseki service.

## Technology Stack

- **Base Image**: Eclipse Temurin 21 JRE Alpine.
- **Database Engine**: Apache Jena / Fuseki (TDB2 storage layout) and Apache Jena command-line tools.
- **Search Engine**: Apache Lucene (integrated via jena-text).
- **Security**: Apache Shiro (HTTP Basic authentication and RBAC).
- **Logging**: log4j2 (configured for Console and JSON structured output).
- **Infrastructure**: Terraform for Azure Resource Group provisioning.
- **Automation**: Github Actions CI/CD pipeline.

## Security Model

- **Multi-Stage Build**: Isolates build tools (`curl`, `tar`) to the builder stage. The runtime image contains only JVM
  and Fuseki binaries.
- **Unprivileged Execution**: Runs under the system user `fuseki` (UID 100, GID 101).
- **Read-Only Root Filesystem**: Compatible with `--read-only`. Requires the following writable paths:
    - `/fuseki/data` (persistent database volume).
    - `/fuseki/run` (ephemeral `tmpfs` volume for runtime lock and shiro configuration).
    - `/tmp` (ephemeral `tmpfs` volume for JVM temporary allocations).

## HTTP API Endpoints

Exposed on port `3030`:

- **SPARQL Query**: `/<dataset-name>/query` (Basic Auth required)
- **SPARQL Update**: `/<dataset-name>/update` (Basic Auth required)
- **SHACL Validation**: `/<dataset-name>/shacl` (Basic Auth required)
- **Graph Store Protocol**: `/<dataset-name>/data` (Basic Auth required)
- **Health Check**: `/$/ping` (unauthenticated, returns ISO 8601 timestamp)
- **Metrics/Status**: `/$/status` (Basic Auth required)

## Environment Variables

| Variable            | Description                                    | Default                                                   |
|---------------------|------------------------------------------------|-----------------------------------------------------------|
| `FUSEKI_CONFIG_DIR` | Directory containing configuration files       | `/fuseki/config`                                          |
| `FUSEKI_DATA`       | Path to persistent database directory          | `/fuseki/data`                                            |
| `FUSEKI_RUN`        | Directory for transient runtime state          | `/fuseki/run`                                             |
| `FUSEKI_HOME`       | Directory containing Fuseki binaries           | `/fuseki/app`                                             |
| `FUSEKI_BASE`       | Configuration and runtime base directory       | Value of `FUSEKI_RUN`                                     |
| `JENA_HOME`         | Directory containing Apache Jena CLI tools     | `/fuseki/app/jena-cli`                                    |
| `REQUIRE_LUCENE`    | Enforces Lucene index configuration on startup | `true`                                                    |
| `LOGGING`           | JVM logging configuration options              | `-Dlog4j.configurationFile=$FUSEKI_CONFIG_DIR/log4j2.xml` |
| `JVM_ARGS`          | JVM memory limits and configurations           | `-Xms512m -Xmx1g`                                         |
| `SSL_CERT_FILE`     | CA certificates trust bundle path              | `/etc/ssl/certs/ca-certificates.crt`                      |

## Configuration Defaults

Defined in `config/config.ttl`:

- RDF service named `/default`.
- Lucene fulltext search indexing enabled on:
    - `rdfs:label`, `skos:prefLabel`, `skos:altLabel` mapped to field `text`.
    - `rdfs:comment`, `skos:definition` mapped to field `text_long`.
- TDB2 data location: `/fuseki/data/default`.
- Lucene index location: `/fuseki/data/default-lucene`.
