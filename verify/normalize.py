"""Value normalisation shared by every reconciliation control.

The rules (also listed in docs/CONVERSION_PLAYBOOK.md):

* NULL stays NULL and is never equal to '' (empty string).
* Strings are compared exactly after Unicode NFC normalisation; no trimming,
  no case folding. Leading/trailing whitespace is data.
* Exact numerics (int, bigint, decimal, money, numeric) are compared as
  decimals quantised to 6 places (ROUND_HALF_EVEN). This absorbs only the
  difference in division scale between engines; MONEY's 4-decimal
  truncation is still visible.
* bit/boolean -> 0/1.
* datetime2/timestamp -> ISO-8601 to the millisecond.
* datetimeoffset/timestamptz -> the UTC instant, ISO-8601 to the millisecond.
* uniqueidentifier/uuid -> lower-case canonical text.
* JSON text (FOR JSON vs json_build_object) is parsed and compared
  structurally, numbers as decimals; key order is ignored, null members are not.
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
import uuid
from datetime import date, datetime, time, timezone
from decimal import ROUND_HALF_EVEN, Decimal

Q6 = Decimal("0.000001")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


def norm(v):
    if v is None:
        return None
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, (int, Decimal)):
        return Decimal(v).quantize(Q6, rounding=ROUND_HALF_EVEN)
    if isinstance(v, float):
        return Decimal(repr(v)).quantize(Q6, rounding=ROUND_HALF_EVEN)
    if isinstance(v, datetime):
        if v.tzinfo is not None:
            return v.astimezone(timezone.utc).replace(tzinfo=None).isoformat(timespec="milliseconds") + "Z"
        return v.isoformat(timespec="milliseconds")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, time):
        return v.isoformat(timespec="milliseconds")
    if isinstance(v, uuid.UUID):
        return str(v)
    if isinstance(v, (bytes, bytearray, memoryview)):
        return bytes(v).hex()
    if isinstance(v, str):
        if UUID_RE.match(v):
            return v.lower()
        return unicodedata.normalize("NFC", v)
    if isinstance(v, (dict, list)):
        return norm_json(v)
    return str(v)


def norm_json(v):
    if isinstance(v, str):
        try:
            v = json.loads(v, parse_float=Decimal)
        except ValueError:
            return norm(v)
    if isinstance(v, dict):
        return tuple(sorted((k, norm_json(x)) for k, x in v.items()))
    if isinstance(v, list):
        return tuple(norm_json(x) for x in v)
    return norm(v)


def norm_row(row, drop: set[int] | None = None, json_cols: set[int] | None = None) -> tuple:
    out = []
    for i, v in enumerate(row):
        if drop and i in drop:
            continue
        out.append(norm_json(v) if json_cols and i in json_cols else norm(v))
    return tuple(out)


def column_digest(values) -> str:
    h = hashlib.sha256()
    for v in values:
        h.update(repr(norm(v)).encode("utf-8"))
        h.update(b"\x1f")
    return h.hexdigest()[:16]
