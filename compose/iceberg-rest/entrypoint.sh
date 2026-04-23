#!/usr/bin/env bash
# ============================================================
# entrypoint.sh
# Runs iceberg-rest and filters the credential-dumping line.
#
# Primary suppression: JAVA_TOOL_OPTIONS sets JUL logging.properties
# in the Dockerfile, which prevents the credential line from being
# emitted at all. This grep filter is defense-in-depth in case the
# log message wording changes across Iceberg REST versions.
#
# set -o pipefail: propagates Java's exit code through the pipe so
# Docker sees a non-zero exit if the JVM crashes, not grep's code.
# ============================================================
set -o pipefail

java -jar /usr/lib/iceberg-rest/iceberg-rest-image-all.jar "$@" 2>&1 \
  | grep --line-buffered -v "Creating catalog with properties"
