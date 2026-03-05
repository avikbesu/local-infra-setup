-- ============================================================
-- config/postgres/1-iceberg-setup.sql
--
-- Creates any extra databases beyond the default POSTGRES_DB.
-- Executed first by postgres-init (1- prefix).
-- Add future databases here — one \gexec block per database.
--
-- Pattern: Postgres has no CREATE DATABASE IF NOT EXISTS, so we
-- build the statement as a string and filter with WHERE NOT EXISTS,
-- then \gexec pipes each result row back into psql as a statement.
-- Zero rows → nothing executes → no error on re-run.
-- ============================================================

-- Create the Iceberg catalog database (used by iceberg-rest via JDBC).
-- Safe to re-run: no-ops if the database already exists.
SELECT 'CREATE DATABASE iceberg'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'iceberg'
)\gexec