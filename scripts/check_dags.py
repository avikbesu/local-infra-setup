#!/usr/bin/env python3
"""
scripts/check_dags.py

Validate that all Airflow DAGs under dags/ import without errors.

Exit codes:
    0 — all DAGs valid
    1 — one or more import errors found
    2 — DagBag initialization failed (environment issue)

Invoked by: make check-dags or scripts/check-deps.sh
"""

from __future__ import annotations

import logging
import sys

from airflow.models import DagBag

logger = logging.getLogger(__name__)


def check_dags(dags_folder: str | None = None) -> int:
    """
    Scan DAGs for import errors and report findings.

    Args:
        dags_folder: Path to the DAGs directory. Defaults to Airflow's
            configured dags_folder if not provided.

    Returns:
        Exit code: 0 if all DAGs valid, 1 if import errors found.

    Raises:
        SystemExit: Code 2 if DagBag initialization fails entirely
            (e.g., missing Airflow config or broken environment).
    """
    logger.info("Scanning DAGs for import errors...")

    try:
        dagbag = DagBag(dag_folder=dags_folder)
    except Exception as exc:
        logger.error("Failed to initialize DagBag: %s", exc, exc_info=True)
        print(f"❌  DagBag initialization failed: {exc}", file=sys.stderr)
        return 2

    if dagbag.import_errors:
        logger.warning(
            "Found %d DAG(s) with import errors", len(dagbag.import_errors)
        )
        print(f"\n❌  Found {len(dagbag.import_errors)} DAG(s) with errors:\n")
        for filepath, error in dagbag.import_errors.items():
            print(f"  File:  {filepath}")
            print(f"  Error: {error}\n")
        return 1

    dag_count = len(dagbag.dags)
    logger.info("All %d DAGs valid", dag_count)
    print(f"✅  All {dag_count} DAGs are valid.\n")
    return 0


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    sys.exit(check_dags())
