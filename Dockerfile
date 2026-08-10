# --- Stage 1: Build & Download dependencies + Custom JRE ---
FROM eclipse-temurin:21-jdk-alpine AS builder

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
    && apk add --no-cache curl tar binutils findutils

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
    && mv "/tmp/apache-jena-${JENA_CLI_TOOLS_VERSION}"/* /fuseki/jena-cli/

# Prune unnecessary files (Windows scripts, sources, documentation)
RUN find /fuseki -type f \( -name "*.bat" -o -name "*.cmd" -o -name "*.exe" \) -delete \
    && rm -rf /fuseki/app/fuseki-server.bat /fuseki/jena-cli/bat

# Build custom minimal JRE using jdeps + jlink
#hadolint ignore=SC2046
RUN java --list-modules | cut -d'@' -f1 > /tmp/valid_modules.txt \
    && RAW_DEPS=$(jdeps \
      --multi-release 21 \
      --ignore-missing-deps \
      --print-module-deps \
      --recursive \
      $(find /fuseki -name "*.jar") 2>&1 || true) \
    && MODULES=$(echo "$RAW_DEPS" \
      | tr ',' '\n' \
      | grep -oE '^[a-z0-9\._]+$' \
      | grep -F -x -f /tmp/valid_modules.txt \
      | sort -u \
      | paste -sd, -) \
    && echo "Validated JDK modules: ${MODULES}" \
    && jlink \
      --add-modules "${MODULES},jdk.unsupported,jdk.crypto.ec,jdk.zipfs,java.naming,java.security.jgss,java.sql,java.desktop,java.management" \
      --strip-debug \
      --no-man-pages \
      --no-header-files \
      --compress=2 \
      --output /custom-jre

# --- Stage 2: Final minimal runtime ---
FROM alpine:3.20

# Set environment variables
ENV FUSEKI_ROOT=/fuseki \
    FUSEKI_HOME=/fuseki/app \
    FUSEKI_CONFIG_DIR=/fuseki/config \
    FUSEKI_DATA=/fuseki/data \
    FUSEKI_RUN=/fuseki/run \
    JVM_ARGS="-Xms512m -Xmx1g" \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    JENA_HOME=/fuseki/app/jena-cli \
    JAVA_HOME=/custom-jre \
    PATH="/custom-jre/bin:/fuseki/app/jena-cli/bin:${PATH}"

# Install minimal runtime system utilities and upgrade OS packages
#hadolint ignore=DL3018
RUN sed -i 's/https/http/g' /etc/apk/repositories \
    && apk upgrade --no-cache \
    && apk add --no-cache ca-certificates tzdata bash curl

# Create non-privileged user and group with explicit UID/GID
RUN addgroup -g 101 -S fuseki && adduser -u 100 -S -G fuseki -h /fuseki -s /sbin/nologin fuseki

# Create folders and set ownership
RUN mkdir -p /fuseki/config /fuseki/data /fuseki/run /fuseki/app \
    && chown -R fuseki:fuseki /fuseki

# Copy custom minimal JRE from builder stage
COPY --from=builder /custom-jre /custom-jre

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
