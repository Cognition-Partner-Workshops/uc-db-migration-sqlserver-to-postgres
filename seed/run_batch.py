"""Run the legacy nightly batch (dbo.usp_batch_nightly) on SQL Server.

SQL Server Express has no SQL Server Agent, so the nightly job is started from
here (or cron / EventBridge in the target design). By default the run is
rolled back so the source estate stays in its seeded state; pass --commit to
keep the changes (then re-run `make seed` before reconciling).
With --ns, the converted PostgreSQL routine is run too, if present.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import check_namespace, mssql_connect, pg_connect  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-date", default="2026-11-01")
    parser.add_argument("--commit", action="store_true")
    parser.add_argument("--ns", help="also run <ns>.usp_batch_nightly on PostgreSQL if converted")
    args = parser.parse_args()

    ms = mssql_connect(autocommit=False)
    cur = ms.cursor()
    cur.execute("EXEC dbo.usp_batch_nightly @run_date = ?", args.run_date)
    while cur.description is None and cur.nextset():
        pass
    cols = [d[0] for d in cur.description]
    print(f"SQL Server dbo.usp_batch_nightly @run_date={args.run_date}")
    for row in cur.fetchall():
        print("  " + ", ".join(f"{c}={v}" for c, v in zip(cols, row)))
    ms.commit() if args.commit else ms.rollback()
    print("  committed" if args.commit else "  rolled back (use COMMIT=1 to keep)")

    if args.ns:
        ns = check_namespace(args.ns)
        pg = pg_connect()
        pcur = pg.cursor()
        pcur.execute(
            "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
            "WHERE n.nspname = %s AND p.proname = 'usp_batch_nightly'",
            (ns,),
        )
        if not pcur.fetchone():
            print(f"PostgreSQL {ns}.usp_batch_nightly: NOT CONVERTED")
            return
        pcur.execute(f"SELECT * FROM {ns}.usp_batch_nightly(p_run_date => %s)", (args.run_date,))
        cols = [d[0] for d in pcur.description]
        print(f"PostgreSQL {ns}.usp_batch_nightly")
        for row in pcur.fetchall():
            print("  " + ", ".join(f"{c}={v}" for c, v in zip(cols, row)))
        pg.commit() if args.commit else pg.rollback()


if __name__ == "__main__":
    main()
