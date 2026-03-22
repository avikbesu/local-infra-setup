# ============================================================
# compose/iceberg-rest/Dockerfile
# Extends tabulario/iceberg-rest to suppress the startup log
# that dumps credentials. Uses Java Util Logging (JUL) —
# the jar bundles no logback or log4j.
#
# WORKDIR must not be overridden — entrypoint resolves the jar
# relative to /usr/lib/iceberg-rest (the base image WORKDIR).
# ============================================================
ARG ICEBERG_REST_VERSION=1.6.0
FROM tabulario/iceberg-rest:${ICEBERG_REST_VERSION}

USER root
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
# restore original UID — check with: docker inspect tabulario/iceberg-rest:1.6.0 | grep User
USER iceberg:iceberg   


# COPY logback.xml /logback.xml
# ENV JAVA_TOOL_OPTIONS="-Dlogback.configurationFile=/logback.xml"

# COPY logging.properties /usr/lib/iceberg-rest/logging.properties
# ENV JAVA_TOOL_OPTIONS="-Djava.util.logging.config.file=/usr/lib/iceberg-rest/logging.properties"

# COPY simplelogger.properties /usr/lib/iceberg-rest/simplelogger.properties

# ENV JAVA_TOOL_OPTIONS="-Dorg.slf4j.simpleLogger.log.org.apache.iceberg.rest.RESTCatalogServer=warn"

COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]