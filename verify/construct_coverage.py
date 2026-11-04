"""Check that every T-SQL construct the demo promises appears in source/sqlserver/.

Comments are stripped before matching, so a construct only counts when it is
real code. Writes work/coverage.md and exits 1 if any construct is missing.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "source" / "sqlserver"

CONSTRUCTS = [
    ("IDENTITY", r"\bIDENTITY\s*\("),
    ("SCOPE_IDENTITY()", r"\bSCOPE_IDENTITY\s*\(\s*\)"),
    ("OUTPUT INSERTED.*", r"\bOUTPUT\s+inserted\."),
    ("MERGE", r"^\s*MERGE\b"),
    ("CROSS APPLY", r"\bCROSS\s+APPLY\b"),
    ("OUTER APPLY", r"\bOUTER\s+APPLY\b"),
    ("TOP (n)", r"\bTOP\s*\(\s*\d+\s*\)"),
    ("TOP ... WITH TIES", r"\bTOP\s*\([^)]*\)\s*WITH\s+TIES\b"),
    ("temp tables (#t)", r"\bCREATE\s+TABLE\s+#\w+"),
    ("table variables", r"\bDECLARE\s+@\w+\s+TABLE\b"),
    ("cursor", r"\bDECLARE\s+\w+\s+CURSOR\b"),
    ("@@FETCH_STATUS", r"@@FETCH_STATUS"),
    ("TRY...CATCH", r"\bBEGIN\s+CATCH\b"),
    ("THROW", r"\bTHROW\s+\d+"),
    ("RAISERROR", r"\bRAISERROR\s*\("),
    ("sp_executesql", r"\bsp_executesql\b"),
    ("STRING_AGG", r"\bSTRING_AGG\s*\("),
    ("FOR JSON PATH", r"\bFOR\s+JSON\s+PATH\b"),
    ("PIVOT", r"\bPIVOT\s*\("),
    ("DATEADD", r"\bDATEADD\s*\("),
    ("DATEDIFF", r"\bDATEDIFF\s*\("),
    ("EOMONTH", r"\bEOMONTH\s*\("),
    ("ISNULL", r"\bISNULL\s*\("),
    ("COALESCE", r"\bCOALESCE\s*\("),
    ("IIF", r"\bIIF\s*\("),
    ("money", r"\bMONEY\b"),
    ("decimal(19,4)", r"\bDECIMAL\s*\(\s*19\s*,\s*4\s*\)"),
    ("uniqueidentifier", r"\bUNIQUEIDENTIFIER\b"),
    ("NEWID()", r"\bNEWID\s*\(\s*\)"),
    ("datetime2", r"\bDATETIME2\b"),
    ("datetimeoffset", r"\bDATETIMEOFFSET\b"),
    ("case-insensitive collation", r"\bCOLLATE\s+\w+_CI_\w+"),
    ("ROWVERSION", r"\bROWVERSION\b"),
    ("sequence", r"\bCREATE\s+SEQUENCE\b"),
    ("computed column", r"\bAS\s*\([^)]*\)\s*PERSISTED\b"),
    ("filtered index", r"\bCREATE\s+(?:UNIQUE\s+)?(?:NONCLUSTERED\s+)?INDEX\b[^;]*?\bWHERE\b"),
    ("triggers (inserted/deleted)", r"\bCREATE\s+(?:OR\s+ALTER\s+)?TRIGGER\b"),
    ("@@ROWCOUNT", r"@@ROWCOUNT"),
]


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def main() -> None:
    files = {p.relative_to(ROOT).as_posix(): strip_comments(p.read_text(encoding="utf-8")) for p in sorted(SOURCE.rglob("*.sql"))}
    rows, missing = [], []
    for name, pattern in CONSTRUCTS:
        rx = re.compile(pattern, re.I | re.M | re.S)
        hits = [f for f, text in files.items() if rx.search(text)]
        if not hits:
            missing.append(name)
        rows.append((name, len(hits), Path(hits[0]).name if hits else "-"))
    lines = ["| Construct | Files | Example |", "|---|---:|---|"]
    lines += [f"| {n} | {c} | `{e}` |" for n, c, e in rows]
    out = ROOT / "work" / "coverage.md"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"\n{len(CONSTRUCTS) - len(missing)}/{len(CONSTRUCTS)} constructs present in {len(files)} source files")
    if missing:
        print(f"MISSING: {', '.join(missing)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
