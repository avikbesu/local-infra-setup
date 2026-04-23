# FAQ

## Issues

### Docker Compose profiles

<details>
<summary>[Issue 1] iceberg-rest fails with "database does not exist" when combining pipeline and query profiles</summary>

- **Issue**:

  ```bash
  docker compose --profile pipeline --profile query up -d
  # iceberg-rest crashes: FATAL: database "iceberg" does not exist
  ```

- **Root cause**:  
  The `postgres-init` one-shot container (which creates the `iceberg` database) belongs to the `db` and `query` profiles — not `pipeline`. Starting `--profile pipeline --profile query` without `--profile db` skips `postgres-init`, so the `iceberg` database is never created.

- **Resolution**:  
  Always use `make query` instead of raw profile flags when combining the pipeline and query stacks. The `make query` target explicitly includes `--profile db`, ensuring `postgres-init` runs first.

  ```bash
  # Correct
  make query          # starts storage + db + query profiles
  make pipeline       # can run separately or alongside

  # Broken — skips postgres-init
  docker compose --profile pipeline --profile query up -d
  ```

  If you need to run raw compose commands, always include `--profile db`:
  ```bash
  docker compose --profile db --profile pipeline --profile query up -d
  ```

</details>

---

### Airflow image

<details>
<summary> [Issue 1] Airflow dags are not running </summary>

  - **Issue**:

    ```bash
    Executor LocalExecutor(parallelism=32) reported that the task instance <TaskInstance: 3_xcom_multi_operator_demo.task_1 manual__2026-03-19T18:45:48.160450+00:00 [queued]> finished with state failed, but the task instance's state attribute is queued. Learn more: https://airflow.apache.org/docs/apache-airflow/stable/troubleshooting.html#task-state-changed-externally
    ```
  - **Resolution**:  
    - in docker compose, airflow component dependencies are not proper. like: `postgres -> airflow init -> airflow api-server -> airflow scheduler`
</details>

### Iceberg-rest image

<details>
<summary> [Issue 1] iceberg-rest container prints credentials in log</summary>

  - **Issue**:

    ```bash
    2026-03-21T18:38:14.807 INFO  [org.apache.iceberg.rest.RESTCatalogServer] - Creating catalog with properties: {jdbc.password=3mHAgksDQ-5wsVrARZoMJuTQ, s3.path-style-access=true, jdbc.user=airflow, s3.endpoint=http://minio:9000, io-impl=org.apache.iceberg.aws.s3.S3FileIO, catalog-impl=org.apache.iceberg.jdbc.JdbcCatalog, warehouse=s3://iceberg-warehouse/, uri=jdbc:postgresql://postgres:5432/iceberg}
    ```
  - **Resolution**:  
    - Used entrypoint.sh to filter out logs.
    - Applied below, not resolved:
      - &#10008; added `logback.xml`
      - &#10008; added `logging.properties`
      - &#10008; added `simplelogger.properties`

</details>


<details>
<summary> [Issue 2] iceberg-rest container failing in health check</summary>

  - **Issue**:
    - no error message from container
    - `make query` command returns ` ✘ Container iceberg-rest            Error dependency iceberg-rest failed to start ` message.
  - **Resolution**:  
    - The root cause is clear from the logs: iceberg-rest is starting successfully (Jetty is up on port 8181), but the healthcheck uses curl which isn't present in the tabulario/iceberg-rest image. It's a minimal JVM image with no HTTP client tools. The fix is to replace the curl healthcheck with a bash TCP check, which requires no external tools.
</details>




### Trino image

<details>
<summary> [Issue 1] trino container has missing config </summary>

  - **Issue**:

    ```bash
    Errors:
      1) Defunct property 'query.max-total-memory-per-node' (class [class io.trino.memory.NodeMemoryConfig]) cannot be configured.
      2) Configuration property 'query.max-total-memory-per-node' was not used
    ```
  - **Resolution**:  
    - Removed that config for now.
</details>


