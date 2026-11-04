"""Build a PostgreSQL namespace from migrations/ (plus optional overlays).

Drops and recreates schema NS, runs every numbered migration in file-name
order with $(NS) substituted, and finishes with the load from `raw`.

Usage:
    python seed/deploy.py --ns dev
    python seed/deploy.py --ns naive --overlay naive_conversion
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import REPO_ROOT, check_namespace, pg_connect  # noqa: E402


def migration_files(overlays: list[str]) -> list[Path]:
    files = {p.name: p for p in (REPO_ROOT / "migrations").glob("*.sql")}
    for overlay in overlays:
        for p in (REPO_ROOT / overlay).glob("*.sql"):
            files[p.name] = p  # an overlay file replaces a same-named migration
    return [files[name] for name in sorted(files)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ns", required=True, help="target schema, e.g. dev")
    parser.add_argument("--overlay", action="append", default=[], help="extra directory of numbered .sql files")
    args = parser.parse_args()
    ns = check_namespace(args.ns)

    conn = pg_connect()
    cur = conn.cursor()
    cur.execute("SELECT to_regclass('raw.dbo_policy') IS NOT NULL")
    if not cur.fetchone()[0]:
        raise SystemExit("raw schema is empty: run `make seed` first")
    cur.execute(f'DROP SCHEMA IF EXISTS "{ns}" CASCADE')
    cur.execute(f'CREATE SCHEMA "{ns}"')
    cur.execute(f'SET search_path = "{ns}", public')
    files = migration_files(args.overlay)
    for path in files:
        sql = path.read_text(encoding="utf-8").replace("$(NS)", ns)
        try:
            cur.execute(sql)
        except Exception as exc:
            conn.rollback()
            raise SystemExit(f"{path.relative_to(REPO_ROOT)}: {exc}") from exc
    conn.commit()
    conn.close()
    print(f"built namespace {ns} from {len(files)} migration files")


if __name__ == "__main__":
    main()
