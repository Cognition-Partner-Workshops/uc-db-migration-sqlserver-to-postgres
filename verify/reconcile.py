"""Reconcile the legacy SQL Server estate against a PostgreSQL namespace.

Controls (see verify/controls.py and verify/normalize.py):
  * per table: COUNT(*) plus an ordered (by key) checksum per column
  * per sequence: next value position
  * per function / view / procedure / trigger: output parity on fixed inputs;
    write paths run inside a transaction that is rolled back on both engines
    and are followed by state queries
  * business rules: must hold on both engines and agree

Status per control: PASS, FAIL, or NOT CONVERTED (Phase 2 object not present in
the namespace). Writes work/reconcile/report.md (+ report.json) and exits 1 on
any FAIL.

Usage: python verify/reconcile.py --ns dev [--mode test|full] [--report PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "seed"))
from controls import BUSINESS_RULES, CONTROLS, SEQUENCES, TABLES, Control  # noqa: E402
from db import REPO_ROOT, check_namespace, mssql_connect, pg_connect  # noqa: E402
from normalize import column_digest, norm, norm_row  # noqa: E402

PASS, FAIL, NOT_CONVERTED = "PASS", "FAIL", "NOT CONVERTED"
MSSQL_MSG_RE = re.compile(r"\[SQL Server\](.*?)(?: \(\d+\))?(?: \(SQL\w+\))?$", re.S)


def mssql_error(exc: Exception) -> str:
    text = exc.args[1] if len(exc.args) > 1 else str(exc)
    msgs = MSSQL_MSG_RE.findall(text.split(";")[0]) or [text]
    return msgs[0].strip()


def pg_error(exc: Exception) -> str:
    diag = getattr(exc, "diag", None)
    return (diag.message_primary if diag and diag.message_primary else str(exc)).strip()


def fetch_mssql(cur, sql: str, params=()) -> list[tuple]:
    cur.execute(sql, params) if params else cur.execute(sql)
    rows: list[tuple] = []
    while True:
        if cur.description:
            rows = [tuple(r) for r in cur.fetchall()]  # last result set wins
        if not cur.nextset():
            break
    return rows


def fetch_pg(cur, sql: str, params=()) -> list[tuple]:
    cur.execute(sql, params or None)
    return [tuple(r) for r in cur.fetchall()] if cur.description else []


def diff_rows(src: list[tuple], tgt: list[tuple], ordered: bool) -> str | None:
    if ordered:
        if src == tgt:
            return None
        for i, (a, b) in enumerate(zip(src, tgt)):
            if a != b:
                return f"row {i + 1}: sqlserver={fmt(a)} postgres={fmt(b)}"
        return f"row count sqlserver={len(src)} postgres={len(tgt)}"
    cs, ct = Counter(src), Counter(tgt)
    if cs == ct:
        return None
    only_s = list((cs - ct).elements())[:3]
    only_t = list((ct - cs).elements())[:3]
    parts = [f"rows sqlserver={len(src)} postgres={len(tgt)}"]
    parts += [f"sqlserver only: {fmt(r)}" for r in sorted(only_s, key=repr)]
    parts += [f"postgres only: {fmt(r)}" for r in sorted(only_t, key=repr)]
    return "; ".join(parts)


def fmt(row) -> str:
    def one(v):
        if v is None:
            return "NULL"
        return str(v.normalize()) if hasattr(v, "normalize") else str(v)

    return "(" + ", ".join(one(v) for v in row) + ")"


class Reconciler:
    def __init__(self, ns: str, mode: str) -> None:
        self.ns = ns
        self.mode = mode
        self.ms = mssql_connect(autocommit=False)
        self.pg = pg_connect()
        self.results: list[dict] = []
        cur = self.pg.cursor()
        cur.execute("SELECT 1 FROM pg_namespace WHERE nspname = %s", (ns,))
        if not cur.fetchone():
            raise SystemExit(f"namespace {ns!r} does not exist: run `make build NS={ns}` first")
        self.pg.rollback()

    def add(self, group: str, name: str, phase, status: str, detail: str = "", category: str = "") -> None:
        self.results.append({"group": group, "object": name, "category": category, "phase": phase, "status": status, "detail": detail})
        print(f"[{status:13s}] {group:9s} {name}" + (f" -- {detail[:160]}" if status == FAIL else ""))

    # ------------------------------------------------------------------ tables
    def tables(self) -> None:
        ms, pg = self.ms.cursor(), self.pg.cursor()
        for t in TABLES:
            schema, table = t.source.split(".")
            ms.execute("SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(?) AND system_type_id <> 189 ORDER BY column_id", t.source)
            src_cols = [r[0] for r in ms.fetchall() if r[0] not in t.exclude]
            pg.execute(
                "SELECT column_name FROM information_schema.columns WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
                (self.ns, t.target),
            )
            tgt_cols = [r[0] for r in pg.fetchall()]
            missing = [c for c in src_cols if c not in tgt_cols]
            if not tgt_cols:
                self.add("table", t.source, 1, FAIL, f"{self.ns}.{t.target} missing", "table")
                continue
            if missing:
                self.add("table", t.source, 1, FAIL, f"columns missing in target: {missing}", "table")
                continue
            src_n = ms.execute(f"SELECT COUNT_BIG(*) FROM {t.source}").fetchone()[0]
            pg.execute(f"SELECT count(*) FROM {self.ns}.{t.target}")
            tgt_n = pg.fetchone()[0]
            col_list = ", ".join(src_cols)
            src_rows = ms.execute(f"SELECT {', '.join(f'[{c}]' for c in src_cols)} FROM {t.source} ORDER BY {t.key}").fetchall()
            pg.execute(f"SELECT {col_list} FROM {self.ns}.{t.target} ORDER BY {t.key}")
            tgt_rows = pg.fetchall()
            bad = []
            for i, c in enumerate(src_cols):
                if column_digest(r[i] for r in src_rows) != column_digest(r[i] for r in tgt_rows):
                    first = next((j for j, (a, b) in enumerate(zip(src_rows, tgt_rows)) if norm(a[i]) != norm(b[i])), None)
                    where = f" first diff at {t.key}={src_rows[first][src_cols.index(t.key)]}" if first is not None else ""
                    bad.append(f"{c}{where}")
            if src_n != tgt_n or bad:
                self.add("table", t.source, 1, FAIL, f"count {src_n} vs {tgt_n}; column checksum mismatch: {bad}", "table")
            else:
                self.add("table", t.source, 1, PASS, f"{src_n} rows, {len(src_cols)} column checksums", "table")
        self.ms.rollback()
        self.pg.rollback()

    def sequences(self) -> None:
        ms, pg = self.ms.cursor(), self.pg.cursor()
        for src, tgt in SEQUENCES:
            pg.execute(
                "SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
                "WHERE n.nspname = %s AND c.relname = %s AND c.relkind = 'S'",
                (self.ns, tgt),
            )
            if not pg.fetchone():
                self.add("sequence", src, 1, FAIL, "missing", "sequence")
                continue
            # the target must hand out numbers above everything already loaded
            col, table = ("policy_number", "policy") if "policy" in tgt else ("claim_number", "claim")
            pg.execute(f"SELECT last_value, (SELECT max(substr({col}::text, 2)::bigint) FROM {self.ns}.{table}) FROM {self.ns}.{tgt}")
            last, mx = pg.fetchone()
            status = PASS if last >= (mx or 0) else FAIL
            self.add("sequence", src, 1, status, f"last_value {last}, max loaded {mx}", "sequence")
        self.pg.rollback()
        del ms

    # ----------------------------------------------------------------- objects
    def target_exists(self, c: Control) -> bool:
        cur = self.pg.cursor()
        if c.kind == "trigger":
            cur.execute(
                "SELECT 1 FROM pg_trigger t JOIN pg_class r ON r.oid = t.tgrelid JOIN pg_namespace n "
                "ON n.oid = r.relnamespace WHERE n.nspname = %s AND t.tgname = %s",
                (self.ns, c.target),
            )
        elif c.kind == "view":
            cur.execute("SELECT 1 FROM pg_views WHERE schemaname = %s AND viewname = %s", (self.ns, c.target))
        else:
            cur.execute(
                "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = %s AND p.proname = %s",
                (self.ns, c.target),
            )
        found = cur.fetchone() is not None
        self.pg.rollback()
        return found

    def run_case(self, c: Control, case) -> str | None:
        ms, pg = self.ms.cursor(), self.pg.cursor()
        pg_sql = case.pg.replace("{ns}", self.ns)
        drop, jcols = set(case.drop), set(case.json_cols)
        src_err = tgt_err = None
        src = tgt = []
        try:
            src = [norm_row(r, drop, jcols) for r in fetch_mssql(ms, case.mssql, case.params)]
        except Exception as exc:  # noqa: BLE001 - the error itself is compared
            src_err = mssql_error(exc)
            ms.close()  # drop pending result sets so state queries can run
        try:
            pg.execute("SAVEPOINT case_start")
            tgt = [norm_row(r, drop, jcols) for r in fetch_pg(pg, pg_sql, case.params)]
        except Exception as exc:  # noqa: BLE001
            tgt_err = pg_error(exc)
            pg.execute("ROLLBACK TO SAVEPOINT case_start")
        problems = []
        if src_err or tgt_err:
            if not (src_err and tgt_err):
                problems.append(f"error parity: sqlserver={src_err or 'ok'} | postgres={tgt_err or 'ok'}")
            elif src_err != tgt_err:
                problems.append(f"error text: sqlserver={src_err!r} postgres={tgt_err!r}")
        else:
            d = diff_rows(src, tgt, case.ordered)
            if d:
                problems.append(d)
        for mssql_q, pg_q in c.state:
            try:
                s = [norm_row(r) for r in fetch_mssql(self.ms.cursor(), mssql_q)]
            except Exception as exc:  # noqa: BLE001 - legacy proc may have rolled back the harness txn
                s = [("error", mssql_error(exc))]
            t = [norm_row(r) for r in fetch_pg(pg, pg_q.replace("{ns}", self.ns))]
            d = diff_rows(s, t, False)
            if d:
                problems.append(f"state after call: {d}")
        self.ms.rollback()
        self.pg.rollback()
        return "; ".join(problems) or None

    def objects(self) -> None:
        for c in CONTROLS:
            if not self.target_exists(c):
                status = NOT_CONVERTED if c.phase == 2 else FAIL
                self.add(c.kind, c.name, c.phase, status, f"{self.ns}.{c.target} not present", c.category)
                continue
            fails = []
            for case in c.cases:
                problem = self.run_case(c, case)
                if problem:
                    fails.append(f"[{case.label}] {problem}")
            detail = " | ".join(fails) if fails else f"{len(c.cases)} fixed-input case(s) match"
            self.add(c.kind, c.name, c.phase, FAIL if fails else PASS, detail, c.category)

    def rules(self) -> None:
        for name, mssql_q, pg_q, must_be_zero in BUSINESS_RULES:
            s = [norm_row(r) for r in fetch_mssql(self.ms.cursor(), mssql_q)]
            t = [norm_row(r) for r in fetch_pg(self.pg.cursor(), pg_q.replace("{ns}", self.ns))]
            problems = []
            d = diff_rows(s, t, False)
            if d:
                problems.append(d)
            if must_be_zero and (s != [(0,)] and s != [(norm(0),)]):
                problems.append(f"rule violated on SQL Server: {fmt(s[0])}")
            if must_be_zero and t != [(norm(0),)]:
                problems.append(f"rule violated on PostgreSQL: {fmt(t[0])}")
            self.add("rule", name, 1, FAIL if problems else PASS, "; ".join(problems) or f"{len(s)} row(s) agree", "business rule")
            self.ms.rollback()
            self.pg.rollback()


def write_report(path: Path, ns: str, mode: str, results: list[dict], seconds: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    counts = Counter(r["status"] for r in results)
    lines = [
        f"# Reconciliation report: `{ns}`",
        "",
        f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} in {seconds:.1f}s, mode `{mode}`. "
        "Source: local SQL Server 2022 Express (`pc_insurance`). Target: PostgreSQL namespace "
        f"`{ns}`.",
        "",
        f"**PASS {counts.get(PASS, 0)} · FAIL {counts.get(FAIL, 0)} · NOT CONVERTED {counts.get(NOT_CONVERTED, 0)}**",
        "",
        "| Status | Group | Object | Category | Phase | Detail |",
        "|---|---|---|---|---|---|",
    ]
    order = {FAIL: 0, NOT_CONVERTED: 2, PASS: 1}
    for r in sorted(results, key=lambda r: (order[r["status"]], r["group"], r["object"])):
        detail = r["detail"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {r['status']} | {r['group']} | `{r['object']}` | {r['category']} | {r['phase']} | {detail} |")
    lines += ["", "Normalisation rules: see `verify/normalize.py` and docs/CONVERSION_PLAYBOOK.md.", ""]
    path.write_text("\n".join(lines), encoding="utf-8")
    path.with_suffix(".json").write_text(json.dumps({"namespace": ns, "results": results}, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ns", required=True)
    parser.add_argument(
        "--mode", choices=["full", "test"], default="full", help="test: CI mode, skips nothing but prints a one-line summary per control"
    )
    parser.add_argument("--report", default=str(REPO_ROOT / "work" / "reconcile" / "report.md"))
    args = parser.parse_args()
    ns = check_namespace(args.ns)
    started = time.time()
    rec = Reconciler(ns, args.mode)
    rec.tables()
    rec.sequences()
    rec.objects()
    rec.rules()
    write_report(Path(args.report), ns, args.mode, rec.results, time.time() - started)
    counts = Counter(r["status"] for r in rec.results)
    print(f"\n{ns}: PASS {counts.get(PASS, 0)}, FAIL {counts.get(FAIL, 0)}, NOT CONVERTED {counts.get(NOT_CONVERTED, 0)} -> {args.report}")
    sys.exit(1 if counts.get(FAIL) else 0)


if __name__ == "__main__":
    main()
