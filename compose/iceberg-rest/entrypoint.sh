#!/bin/bash
# ============================================================
# entrypoint.sh
# Runs iceberg-rest and filters the credential-dumping line.
#
# Two fixes vs naive `exec java ... | grep ...`:
#   1. No `exec` on the left side of a pipe — exec only replaces
#      the shell for a simple command, not a pipeline. Without it,
#      bash stays as PID 1 and forwards signals correctly.
#   2. grep --line-buffered — grep switches to block buffering
#      when stdout is a pipe, which silences all output until the
#      buffer fills. --line-buffered forces per-line flushing so
#      Docker receives logs immediately.
# ============================================================
java -jar /usr/lib/iceberg-rest/iceberg-rest-image-all.jar "$@" 2>&1 \
  | grep --line-buffered -v "Creating catalog with properties"