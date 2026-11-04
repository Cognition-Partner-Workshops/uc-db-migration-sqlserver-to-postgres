"""Copy every legacy table, as-is, into the PostgreSQL `raw` schema.

Reads SQL Server through the read-only migration_reader login and lands the
rows with a mechanical type mapping (no business rules). Namespaced builds
(`make build NS=...`) then load their typed tables from `raw`.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import mssql_connect, pg_connect  # noqa: E402

TYPE_MAP = {
    "int": "integer", "bigint": "bigint", "smallint": "smallint", "tinyint": "smallint",
    "bit": "boolean", "money": "numeric(19,4)", "date": "date", "uniqueidentifier": "uuid",
    "datetimeoffset": "timestamptz", "datetime2": "timestamp", "datetime": "timestamp",
}
SKIP_TYPES = {"timestamp"}  # ROWVERSION: instance-specific, not data


def pg_type(data_type: str, precision, scale) -> str:
    if data_type in ("decimal", "numeric"):
        return f"numeric({precision},{scale})"
    return TYPE_MAP.get(data_type, "text")


def copy_value(v) -> str:
    if v is None:
        return r"\N"
    if isinstance(v, bool):
        return "t" if v else "f"
    s = str(v)
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def main() -> None:
    src = mssql_connect(reader=True)
    cur = src.cursor()
    cur.execute(
        """
        SELECT c.TABLE_SCHEMA, c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE, c.NUMERIC_PRECISION, c.NUMERIC_SCALE,
               COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'IsComputed')
        FROM INFORMATION_SCHEMA.COLUMNS AS c
        JOIN INFORMATION_SCHEMA.TABLES AS t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE t.TABLE_TYPE = 'BASE TABLE' AND c.TABLE_SCHEMA IN ('dbo', 'ref')
        ORDER BY c.TABLE_SCHEMA, c.TABLE_NAME, c.ORDINAL_POSITION
        """
    )
    tables: dict[tuple[str, str], list[tuple[str, str]]] = {}
    for schema, table, col, dtype, prec, scale, computed in cur.fetchall():
        if dtype in SKIP_TYPES or computed:
            continue
        tables.setdefault((schema, table), []).append((col, pg_type(dtype, prec, scale)))

    pg = pg_connect()
    pcur = pg.cursor()
    pcur.execute("DROP SCHEMA IF EXISTS raw CASCADE; CREATE SCHEMA raw;")
    for (schema, table), cols in tables.items():
        target = f"raw.{schema}_{table}"
        pcur.execute(f"CREATE TABLE {target} ({', '.join(f'{c} {t}' for c, t in cols)})")
        select_list = ", ".join(
            f"CONVERT(varchar(40), [{c}], 127)" if t in ("timestamptz", "timestamp") else f"[{c}]" for c, t in cols
        )
        cur.execute(f"SELECT {select_list} FROM [{schema}].[{table}]")
        buf = io.StringIO()
        for row in cur.fetchall():
            buf.write("\t".join(copy_value(v) for v in row) + "\n")
        buf.seek(0)
        pcur.copy_expert(f"COPY {target} FROM STDIN", buf)
        print(f"  {target:28s} {pcur.rowcount:>6d} rows")
    pg.commit()
    pg.close()
    src.close()


if __name__ == "__main__":
    main()
