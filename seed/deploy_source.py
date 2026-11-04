"""Create the legacy SQL Server estate from source/sqlserver/ (drops it first).

Usage: python seed/deploy_source.py [--keep]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import REPO_ROOT, SQLSERVER_DB, mssql_connect, split_batches  # noqa: E402

SOURCE = REPO_ROOT / "source" / "sqlserver"
# Dependency order: schema, functions, views, procedures, triggers.
ORDER = ["schema", "functions", "views", "procedures", "triggers"]


def source_files() -> list[Path]:
    files: list[Path] = []
    for folder in ORDER:
        files.extend(sorted((SOURCE / folder).rglob("*.sql")))
    return files


def run_file(cur, path: Path) -> None:
    sql = path.read_text(encoding="utf-8").replace("$(DB)", SQLSERVER_DB)
    for batch in split_batches(sql):
        try:
            cur.execute(batch)
            while cur.nextset():
                pass
        except Exception as exc:  # pragma: no cover - surfaced to the operator
            raise SystemExit(f"{path.relative_to(REPO_ROOT)}: {exc}") from exc


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="do not drop an existing database")
    args = parser.parse_args()

    master = mssql_connect("master")
    cur = master.cursor()
    if not args.keep:
        cur.execute(
            f"IF DB_ID(N'{SQLSERVER_DB}') IS NOT NULL BEGIN "
            f"ALTER DATABASE [{SQLSERVER_DB}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
            f"DROP DATABASE [{SQLSERVER_DB}]; END"
        )
    run_file(cur, SOURCE / "000_database.sql")
    master.close()

    conn = mssql_connect()
    cur = conn.cursor()
    files = source_files()
    for path in files:
        run_file(cur, path)
    conn.close()
    print(f"deployed {len(files)} source files into [{SQLSERVER_DB}]")


if __name__ == "__main__":
    main()
