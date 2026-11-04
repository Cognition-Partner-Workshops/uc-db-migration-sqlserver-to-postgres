"""Connection helpers shared by the seed, build and verify scripts.

Both engines are local throwaway containers (docker-compose.yml or the CI
service containers). The SQL Server helper refuses any non-local host so the
harness can never be pointed at a real estate by accident.
"""

from __future__ import annotations

import os
import re
import struct
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg2
import pyodbc

REPO_ROOT = Path(__file__).resolve().parent.parent
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", "mssql", "host.docker.internal"}

SQLSERVER_DB = os.getenv("SQLSERVER_DB", "pc_insurance")
READER_LOGIN = os.getenv("SQLSERVER_READER_USER", "migration_reader")
READER_PASSWORD = os.getenv("SQLSERVER_READER_PASSWORD", "Reader_Local_Only_2026!")


def _sqlserver_host() -> str:
    host = os.getenv("SQLSERVER_HOST", "localhost")
    if host not in LOCAL_HOSTS:
        raise SystemExit(
            f"Refusing to connect to SQL Server host {host!r}: this harness only talks to the local demo container (see AGENTS.md)."
        )
    return host


def mssql_connect(database: str | None = None, *, reader: bool = False, autocommit: bool = True):
    host = _sqlserver_host()
    port = os.getenv("SQLSERVER_PORT", "1433")
    if reader:
        user, password = READER_LOGIN, READER_PASSWORD
    else:
        user = os.getenv("SQLSERVER_USER", "sa")
        password = os.getenv("SQLSERVER_PASSWORD", "Local_Demo_Only_2026!")
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={host},{port};DATABASE={database or SQLSERVER_DB};"
        f"UID={user};PWD={password};TrustServerCertificate=yes;Encrypt=no"
    )
    conn = pyodbc.connect(conn_str, autocommit=autocommit)
    conn.add_output_converter(-155, _datetimeoffset)
    return conn


def _datetimeoffset(raw: bytes | None):
    """pyodbc has no native DATETIMEOFFSET type (SQL type -155)."""
    if raw is None:
        return None
    y, mo, d, h, mi, s, ns, oh, om = struct.unpack("<6hI2h", raw)
    tz = timezone(timedelta(hours=oh, minutes=om))
    return datetime(y, mo, d, h, mi, s, ns // 1000, tzinfo=tz)


def pg_connect(autocommit: bool = False):
    conn = psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "55432")),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD", "postgres"),
        dbname=os.getenv("PGDATABASE", "pc_insurance"),
        options="-c timezone=UTC -c lc_monetary=C",
    )
    conn.autocommit = autocommit
    return conn


NAMESPACE_RE = re.compile(r"^[a-z][a-z0-9_]{0,30}$")


def check_namespace(ns: str) -> str:
    if not NAMESPACE_RE.match(ns) or ns in {"raw", "public", "pg_catalog", "information_schema"}:
        raise SystemExit(f"Invalid namespace {ns!r}: use lowercase letters, digits and _ (not raw/public).")
    return ns


GO_RE = re.compile(r"^\s*GO\s*;?\s*$", re.IGNORECASE | re.MULTILINE)


def split_batches(sql: str) -> list[str]:
    return [b.strip() for b in GO_RE.split(sql) if b.strip()]
