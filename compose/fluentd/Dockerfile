# ============================================================
# fluentd/Dockerfile
# Extends official Fluentd image with:
#   - fluent-plugin-s3     → ship logs to MinIO (S3-compatible)
#   - fluent-plugin-multi-format-parser → handle JSON + plain text
# ============================================================
FROM fluent/fluentd:v1.19-2

USER root

RUN gem install \
      fluent-plugin-s3 \
      fluent-plugin-multi-format-parser \
      --no-document \
  # Pre-create buffer directory owned by fluent user so Docker
  # named volume mount doesn't land as root-owned.
  && mkdir -p /fluentd/buffer \
  && chown -R fluent:fluent /fluentd/buffer

USER fluent