ARG AIRFLOW_VERSION=3.2.0
FROM apache/airflow:${AIRFLOW_VERSION}

# Install providers baked-in so containers start instantly (no pip on every run).
RUN pip install --no-cache-dir apache-airflow-providers-hashicorp
