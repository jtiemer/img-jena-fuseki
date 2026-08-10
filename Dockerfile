# --- Stage 1: Build & Download dependencies ---
FROM eclipse-temurin:21-jre-alpine AS builder

# Install CA certificate for TLS interception (corporate networks)
COPY certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

ARG FUSEKI_VERSION
ARG JENA_CLI_TOOLS_VERSION
ENV FUSEKI_HOME=/fuseki/app \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
#hadolint ignore=DL3018
RUN sed -i 's/https/http/g' /etc/apk/repositories \
    && apk upgrade --no-cache \
    && apk add --no-cache curl tar

# Set default shell option to fail-fast on pipes
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Download and extract Apache Jena Fuseki
RUN mkdir -p /fuseki \
    && test -n "${FUSEKI_VERSION}" \
    && curl -fsSL "https://downloads.apache.org/jena/binaries/apache-jena-fuseki-${FUSEKI_VERSION}.tar.gz" \
      | tar -xz -C /tmp \
    && mv "/tmp/apache-jena-fuseki-${FUSEKI_VERSION}" "${FUSEKI_HOME}"

# Download and extract Apache Jena CLI Tools
RUN mkdir -p /fuseki/jena-cli \
    && test -n "${JENA_CLI_TOOLS_VERSION}" \
    && curl -fsSL "https://downloads.apache.org/jena/binaries/apache-jena-${JENA_CLI_TOOLS_VERSION}.tar.gz" \
      | tar -xz -C /tmp \
    && mv "/tmp/apache-jena-${JENA_CLI_TOOLS_VERSION}/"* /fuseki/jena-cli/

# --- Stage 2: Final minimal runtime ---
FROM eclipse-temurin:21-jre-alpine

# Upgrade OS packages to apply security patches
#hadolint ignore=DL3018
RUN apk upgrade --no-cache

# Set environment variables
ENV FUSEKI_ROOT=/fuseki \
    FUSEKI_HOME=/fuseki/app \
    FUSEKI_CONFIG_DIR=/fuseki/config \
    FUSEKI_DATA=/fuseki/data \
    FUSEKI_RUN=/fuseki/run \
    JVM_ARGS="-Xms512m -Xmx1g" \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    JENA_HOME=/fuseki/app/jena-cli \
    PATH="/fuseki/app/jena-cli/bin:${PATH}"

# Create non-privileged user and group with explicit UID/GID
RUN addgroup -g 101 -S fuseki && adduser -u 100 -S -G fuseki -h /fuseki -s /sbin/nologin fuseki

# Create folders and set ownership
RUN mkdir -p /fuseki/config /fuseki/data /fuseki/run /fuseki/app \
    && chown -R fuseki:fuseki /fuseki

# Copy Fuseki and Jena CLI installations from builder stage
COPY --from=builder --chown=fuseki:fuseki /fuseki/app /fuseki/app
COPY --from=builder --chown=fuseki:fuseki /fuseki/jena-cli /fuseki/app/jena-cli

# Copy entrypoint and configurations
COPY --chown=fuseki:fuseki entrypoint.sh /entrypoint.sh
COPY --chown=fuseki:fuseki config/config.ttl /fuseki/config/config.ttl
COPY --chown=fuseki:fuseki config/shiro.ini /fuseki/config/shiro.ini
COPY --chown=fuseki:fuseki config/log4j2.xml /fuseki/config/log4j2.xml

# Ensure execution permissions
RUN chmod +x /entrypoint.sh \
    && chmod +x /fuseki/app/jena-cli/bin/*

# Expose port
EXPOSE 3030

# Mark data volume
VOLUME ["/fuseki/data"]

# Run container as non-privileged user
USER 100

ENTRYPOINT ["/entrypoint.sh"]
