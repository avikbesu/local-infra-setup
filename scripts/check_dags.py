#!/usr/bin/env python3
"""
scripts/check_dags.py

Validate that all Airflow DAGs under dags/ import without errors.

Exit codes:
    0 — all DAGs valid
    1 — one or more import errors found
    2 — DagBag initialization failed (environment issue)

Invoked by: make check-dags
"""

from __future__ import annotations

import logging
import sys
import time


# ── Logging setup (UTC timestamps matching lib/common.sh format) ──────────────

class _UTCFormatter(logging.Formatter):
    converter = time.gmtime

    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        ct = self.converter(record.created)
        return time.strftime(datefmt or "%Y-%m-%dT%H:%M:%SZ", ct)


def _setup_logging(debug: bool = False) -> None:
    level = logging.DEBUG if debug else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(_UTCFormatter(
        fmt="%(asctime)s [%(levelname)-5s] %(message)s",
    ))
    logging.basicConfig(level=level, handlers=[handler], force=True)


log = logging.getLogger(__name__)


# ── Core logic ────────────────────────────────────────────────────────────────

def check_dags(dags_folder: str | None = None) -> int:
    """
    Scan DAGs for import errors and report findings.

    Args:
        dags_folder: Path to the DAGs directory. Defaults to Airflow's
            configured dags_folder if not provided.

    Returns:
        Exit code: 0 if all DAGs valid, 1 if import errors found, 2 on init failure.
    """
    from airflow.models import DagBag

    log.info("Scanning DAGs for import errors...")

    try:
        dagbag = DagBag(dag_folder=dags_folder)
    except Exception as exc:
        log.error("Failed to initialize DagBag: %s", exc, exc_info=True)
        return 2

    if dagbag.import_errors:
        log.warning("Found %d DAG(s) with import errors:", len(dagbag.import_errors))
        for filepath, error in dagbag.import_errors.items():
            log.error("  File:  %s", filepath)
            log.error("  Error: %s", error)
        return 1

    log.info("All %d DAG(s) valid.", len(dagbag.dags))
    return 0


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Validate Airflow DAG imports")
    parser.add_argument("--dags-folder", metavar="PATH", help="Path to DAGs directory")
    parser.add_argument("--debug", action="store_true", help="Enable DEBUG log level")
    args = parser.parse_args()

    _setup_logging(debug=args.debug)
    sys.exit(check_dags(dags_folder=args.dags_folder))
