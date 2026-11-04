"""End-to-end business scenario run on both engines, then compared.

create policyholder -> create policy -> endorse -> take premium payment ->
open claim -> close claim. Each engine runs the scenario in one transaction
that is rolled back afterwards, so the legacy estate is never changed.
Steps whose PostgreSQL routine is not in the namespace (Phase 2 on `main`)
report NOT CONVERTED and the later steps that depend on them are skipped.

Usage: python verify/functional_tests.py --ns dev
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "seed"))
from db import check_namespace, mssql_connect, pg_connect  # noqa: E402
from normalize import norm_row  # noqa: E402
from reconcile import diff_rows, fetch_mssql, fetch_pg  # noqa: E402

AS_OF = "2026-11-01 09:00:00"

# (label, pg routine, mssql sql, pg sql, params(ctx), columns holding generated keys)
STEPS = [
    (
        "create policyholder",
        "usp_policyholder_create",
        "EXEC dbo.usp_policyholder_create @first_name=?, @middle_name=?, @last_name=?, @date_of_birth=?, @email=?, "
        "@iban=?, @address_line=?, @postcode=?, @city=?, @country_code=?",
        "SELECT * FROM {ns}.usp_policyholder_create(p_first_name=>%s, p_middle_name=>%s, p_last_name=>%s, "
        "p_date_of_birth=>%s, p_email=>%s, p_iban=>%s, p_address_line=>%s, p_postcode=>%s, p_city=>%s, p_country_code=>%s)",
        lambda ctx: [
            "Märta",
            None,
            "Öberg",
            "1988-02-29",
            "marta.oberg@example.at",
            "AT61 1904 3002 3457 3201",
            "Mariahilfer Straße 1",
            "1060",
            "Wien",
            "at",
        ],
        (0,),
    ),
    (
        "create policy",
        "usp_policy_create",
        "EXEC dbo.usp_policy_create @policyholder_id=?, @product_code=?, @broker_code=?, @inception_date=?, "
        "@payment_frequency=?, @sum_insured=?, @annual_premium=?, @as_of=?",
        "SELECT * FROM {ns}.usp_policy_create(p_policyholder_id=>%s, p_product_code=>%s, p_broker_code=>%s, "
        "p_inception_date=>%s, p_payment_frequency=>%s::smallint, p_sum_insured=>%s, p_annual_premium=>%s, p_as_of=>%s)",
        lambda ctx: [ctx["policyholder_id"], "Motor-Priv", "brk-0003", "2026-01-31", 4, "18000", "612.3350", AS_OF],
        (0, 1, 2),
    ),
    (
        "endorse policy",
        "usp_policy_endorse",
        "EXEC dbo.usp_policy_endorse @policy_id=?, @effective_from=?, @sum_insured=?, @annual_premium=?, @change_reason=?, @as_of=?",
        "SELECT * FROM {ns}.usp_policy_endorse(p_policy_id=>%s, p_effective_from=>%s, p_sum_insured=>%s, "
        "p_annual_premium=>%s, p_change_reason=>%s, p_as_of=>%s)",
        lambda ctx: [ctx["policy_id"], "2026-04-30", "21000", "700.0050", "Added young driver", AS_OF],
        (0,),
    ),
    (
        "take premium payment",
        "usp_premium_payment_record",
        "EXEC dbo.usp_premium_payment_record @policy_id=?, @amount=?, @method=?, @paid_at=?, @payer_iban=?, @reference_text=?",
        "SELECT * FROM {ns}.usp_premium_payment_record(p_policy_id=>%s, p_amount=>%s, p_method=>%s, p_paid_at=>%s, "
        "p_payer_iban=>%s, p_reference_text=>%s)",
        lambda ctx: [ctx["policy_id"], "153.08375", "card", "2026-03-29 23:30:00 +02:00", None, None],
        (0,),
    ),
    (
        "open claim",
        "usp_claim_open",
        "EXEC dbo.usp_claim_open @policy_number=?, @loss_date=?, @reported_at=?, @cause_code=?, @description=?, @initial_estimate=?",
        "SELECT * FROM {ns}.usp_claim_open(p_policy_number=>%s, p_loss_date=>%s, p_reported_at=>%s, p_cause_code=>%s, "
        "p_description=>%s, p_initial_estimate=>%s)",
        lambda ctx: [ctx["policy_number"].lower(), "2026-05-31", "2026-06-01 07:45:00", "Collision", "", "4250.5050"],
        (0, 1),
    ),
    (
        "close claim",
        "usp_claim_close",
        "EXEC dbo.usp_claim_close @claim_id=?, @as_of=?",
        "SELECT * FROM {ns}.usp_claim_close(p_claim_id=>%s, p_as_of=>%s)",
        lambda ctx: [ctx["claim_id"], AS_OF],
        (0,),
    ),
]

STATE = [
    (
        "policyholder",
        "SELECT first_name, middle_name, last_name, full_name, email, iban, country_code FROM dbo.policyholder WHERE policyholder_id = ?",
        "SELECT first_name, middle_name, last_name, full_name, email, iban, country_code FROM {ns}.policyholder WHERE policyholder_id = %s",
        "policyholder_id",
    ),
    (
        "policy",
        "SELECT status, inception_date, expiry_date, payment_frequency, annual_premium, updated_at FROM dbo.policy WHERE policy_id = ?",
        "SELECT status, inception_date, expiry_date, payment_frequency, annual_premium, updated_at FROM {ns}.policy WHERE policy_id = %s",
        "policy_id",
    ),
    (
        "policy versions",
        "SELECT version_no, effective_from, effective_to, sum_insured, annual_premium, change_reason FROM dbo.policy_version WHERE policy_id = ?",
        "SELECT version_no, effective_from, effective_to, sum_insured, annual_premium, change_reason FROM {ns}.policy_version WHERE policy_id = %s",
        "policy_id",
    ),
    (
        "premium payments",
        "SELECT paid_at, amount, method, payer_iban, reference_text FROM dbo.premium_payment WHERE policy_id = ?",
        "SELECT paid_at, amount, method, payer_iban, reference_text FROM {ns}.premium_payment WHERE policy_id = %s",
        "policy_id",
    ),
    (
        "claim",
        "SELECT loss_date, reported_at, cause_code, status, description, closed_at FROM dbo.claim WHERE claim_id = ?",
        "SELECT loss_date, reported_at, cause_code, status, description, closed_at FROM {ns}.claim WHERE claim_id = %s",
        "claim_id",
    ),
    (
        "claim reserves",
        "SELECT reserve_type, amount, set_by FROM dbo.claim_reserve WHERE claim_id = ?",
        "SELECT reserve_type, amount, set_by FROM {ns}.claim_reserve WHERE claim_id = %s",
        "claim_id",
    ),
    (
        "audit trail",
        "SELECT table_name, action, old_value, new_value, row_count FROM dbo.audit_log WHERE key_value = ?",
        "SELECT table_name, action, old_value, new_value, row_count FROM {ns}.audit_log WHERE key_value = %s",
        "claim_number",
    ),
]

KEYS = {
    "create policyholder": {"policyholder_id": 0},
    "create policy": {"policy_id": 0, "policy_number": 1},
    "open claim": {"claim_id": 0, "claim_number": 1},
}


def routine_exists(pg, ns: str, name: str) -> bool:
    cur = pg.cursor()
    cur.execute("SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = %s AND p.proname = %s", (ns, name))
    return cur.fetchone() is not None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ns", required=True)
    ns = check_namespace(parser.parse_args().ns)
    ms, pg = mssql_connect(autocommit=False), pg_connect()
    sctx: dict = {}
    tctx: dict = {}
    failures = 0
    stopped = None
    try:
        for label, routine, mssql_sql, pg_sql, params, drop in STEPS:
            if stopped:
                print(f"[SKIPPED      ] {label} (depends on {stopped})")
                continue
            if not routine_exists(pg, ns, routine):
                print(f"[NOT CONVERTED] {label}: {ns}.{routine} not present")
                stopped = label
                continue
            src_raw = fetch_mssql(ms.cursor(), mssql_sql, params(sctx))
            tgt_raw = fetch_pg(pg.cursor(), pg_sql.replace("{ns}", ns), params(tctx))
            for key, idx in KEYS.get(label, {}).items():
                sctx[key], tctx[key] = src_raw[0][idx], tgt_raw[0][idx]
            d = diff_rows([norm_row(r, set(drop)) for r in src_raw], [norm_row(r, set(drop)) for r in tgt_raw], True)
            failures += bool(d)
            print(f"[{'FAIL' if d else 'PASS':13s}] {label}" + (f": {d}" if d else ""))
        for label, mssql_q, pg_q, key in STATE:
            if key not in sctx:
                continue
            s = [norm_row(r) for r in fetch_mssql(ms.cursor(), mssql_q, [sctx[key]])]
            t = [norm_row(r) for r in fetch_pg(pg.cursor(), pg_q.replace("{ns}", ns), [tctx[key]])]
            d = diff_rows(s, t, False)
            failures += bool(d)
            print(f"[{'FAIL' if d else 'PASS':13s}] resulting state: {label} ({len(s)} rows)" + (f": {d}" if d else ""))
    finally:
        ms.rollback()
        pg.rollback()
    print(f"\nfunctional tests on {ns}: {'FAILED' if failures else 'OK'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
