"""Create the read-only migration_reader login (db_datareader only).

The raw loader and the reconciliation harness read the legacy estate through
this login so they cannot change it.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import READER_LOGIN, READER_PASSWORD, SQLSERVER_DB, mssql_connect  # noqa: E402


def main() -> None:
    master = mssql_connect("master")
    cur = master.cursor()
    cur.execute(
        f"IF SUSER_ID(N'{READER_LOGIN}') IS NULL "
        f"CREATE LOGIN [{READER_LOGIN}] WITH PASSWORD = N'{READER_PASSWORD.replace(chr(39), chr(39) * 2)}', "
        f"CHECK_POLICY = OFF, DEFAULT_DATABASE = [{SQLSERVER_DB}]"
    )
    master.close()
    conn = mssql_connect()
    cur = conn.cursor()
    cur.execute(
        f"IF USER_ID(N'{READER_LOGIN}') IS NULL CREATE USER [{READER_LOGIN}] FOR LOGIN [{READER_LOGIN}]; "
        f"ALTER ROLE db_datareader ADD MEMBER [{READER_LOGIN}];"
    )
    conn.close()
    print(f"read-only login {READER_LOGIN} ready on [{SQLSERVER_DB}]")


if __name__ == "__main__":
    main()
