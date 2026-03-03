#!/usr/bin/env python3

from airflow.models import DagBag
import sys

def check_dags():
    print("Scanning DAGs for import errors...")
    dagbag = DagBag()

    if dagbag.import_errors:
        print("\nFound the following errors:")
        for filepath, error in dagbag.import_errors.items():
            print(f"\nFile: {filepath}")
            print(f"Error: {error}\n")
        sys.exit(1)
    else:
        print("\nNo import errors found. All DAGs are valid!\n")
        sys.exit(0)

if __name__ == "__main__":
    check_dags()