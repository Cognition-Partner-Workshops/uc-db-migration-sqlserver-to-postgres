"""Reconciliation control registry.

Every legacy object has exactly one entry. `target` is the PostgreSQL object
the control looks for in the namespace; when it is missing the control reports
NOT CONVERTED (Phase 2) or FAIL (Phase 1). Inputs are fixed so runs are
repeatable. Do not edit these controls to make a FAIL pass (see AGENTS.md).
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Table:
    source: str
    target: str
    key: str
    exclude: tuple[str, ...] = ()


TABLES = [
    Table("ref.country", "country", "country_code"),
    Table("ref.product", "product", "product_id"),
    Table("dbo.broker", "broker", "broker_id"),
    Table("dbo.policyholder", "policyholder", "policyholder_id", ("row_ver",)),
    Table("dbo.policy", "policy", "policy_id", ("row_ver",)),
    Table("dbo.policy_version", "policy_version", "policy_version_id"),
    Table("dbo.coverage", "coverage", "coverage_id"),
    Table("dbo.premium_schedule", "premium_schedule", "schedule_id"),
    Table("dbo.premium_payment", "premium_payment", "payment_id"),
    Table("dbo.claim", "claim", "claim_id", ("row_ver",)),
    Table("dbo.claim_reserve", "claim_reserve", "reserve_id"),
    Table("dbo.claim_payment", "claim_payment", "claim_payment_id"),
    Table("dbo.audit_log", "audit_log", "audit_id"),
]

SEQUENCES = [("dbo.seq_policy_number", "seq_policy_number"), ("dbo.seq_claim_number", "seq_claim_number")]


@dataclass
class Case:
    label: str
    mssql: str
    pg: str
    params: list = field(default_factory=list)
    drop: tuple[int, ...] = ()  # output columns holding generated keys
    json_cols: tuple[int, ...] = ()
    ordered: bool = False  # compare in returned order instead of as a multiset


@dataclass
class Control:
    name: str  # legacy object
    kind: str  # function | view | procedure | trigger
    category: str
    phase: int
    target: str  # PostgreSQL object name in the namespace
    cases: list[Case]
    writes: bool = False
    state: list[tuple[str, str]] = field(default_factory=list)  # (mssql, pg) queries run after each case
    setup: list[tuple[str, str]] = field(default_factory=list)  # (mssql, pg) statements run before each case


AUDIT_TAIL = (
    "SELECT TOP (5) table_name, action, key_value, old_value, new_value, row_count FROM dbo.audit_log ORDER BY audit_id DESC",
    "SELECT table_name, action, key_value, old_value, new_value, row_count FROM {ns}.audit_log ORDER BY audit_id DESC LIMIT 5",
)


def C(label, mssql, pg, params=(), **kw) -> Case:
    return Case(label, mssql, pg, list(params), **kw)


CONTROLS: list[Control] = [
    # ---------------------------------------------------------------- functions
    Control(
        "dbo.fn_months_between",
        "function",
        "function",
        1,
        "fn_months_between",
        [
            C(
                "month-end boundaries",
                "SELECT d.f, d.t, dbo.fn_months_between(d.f, d.t) FROM (VALUES "
                "(CAST('2026-01-31' AS date), CAST('2026-03-01' AS date)), ('2024-02-29','2025-02-28'), "
                "('2025-12-31','2026-01-01'), ('2026-03-01','2026-01-31'), ('2023-03-31','2026-03-01')) AS d(f, t)",
                "SELECT d.f, d.t, {ns}.fn_months_between(d.f, d.t) FROM (VALUES "
                "('2026-01-31'::date, '2026-03-01'::date), ('2024-02-29','2025-02-28'), "
                "('2025-12-31','2026-01-01'), ('2026-03-01','2026-01-31'), ('2023-03-31','2026-03-01')) AS d(f, t)",
            ),
        ],
    ),
    Control(
        "dbo.fn_pro_rata",
        "function",
        "function",
        1,
        "fn_pro_rata",
        [
            C(
                "money truncation",
                "SELECT a, d, p, dbo.fn_pro_rata(a, d, p) FROM (VALUES (CAST(200 AS money), 1, 3), (200, 2, 3), "
                "(-200, 1, 3), (1234.5650, 17, 365), (99.995, 1, 2), (100, 1, 0)) AS v(a, d, p)",
                "SELECT a, d, p, {ns}.fn_pro_rata(a, d, p) FROM (VALUES (200::numeric, 1, 3), (200, 2, 3), "
                "(-200, 1, 3), (1234.5650, 17, 365), (99.995, 1, 2), (100, 1, 0)) AS v(a, d, p)",
            ),
        ],
    ),
    Control(
        "dbo.fn_format_name",
        "function",
        "function",
        1,
        "fn_format_name",
        [
            C(
                "NULL, empty and blank middle names",
                "SELECT policyholder_id, dbo.fn_format_name(first_name, middle_name, last_name) FROM dbo.policyholder",
                "SELECT policyholder_id, {ns}.fn_format_name(first_name, middle_name, last_name) FROM {ns}.policyholder",
            ),
        ],
    ),
    Control(
        "dbo.tvf_policy_coverage_summary",
        "function",
        "function",
        1,
        "tvf_policy_coverage_summary",
        [
            C(
                "all policies",
                "SELECT s.* FROM dbo.policy p CROSS APPLY dbo.tvf_policy_coverage_summary(p.policy_id) s",
                "SELECT s.* FROM {ns}.policy p CROSS JOIN LATERAL {ns}.tvf_policy_coverage_summary(p.policy_id) s",
            ),
        ],
    ),
    # -------------------------------------------------------------------- views
    *[
        Control(f"dbo.{v}", "view", "view", 1, v, [C("full view", f"SELECT * FROM dbo.{v}", f"SELECT * FROM {{ns}}.{v}")])
        for v in ("vw_active_policy", "vw_claim_position", "vw_policy_coverage_pivot", "vw_broker_portfolio")
    ],
    # --------------------------------------------------------------------- CRUD
    Control(
        "dbo.usp_policyholder_create",
        "procedure",
        "crud",
        1,
        "usp_policyholder_create",
        [
            C(
                "accented holder, empty middle name",
                "EXEC dbo.usp_policyholder_create @first_name=?, @middle_name=?, @last_name=?, @date_of_birth=?, @email=?, "
                "@iban=?, @address_line=?, @postcode=?, @city=?, @country_code=?",
                "SELECT * FROM {ns}.usp_policyholder_create(p_first_name=>%s, p_middle_name=>%s, p_last_name=>%s, "
                "p_date_of_birth=>%s, p_email=>%s, p_iban=>%s, p_address_line=>%s, p_postcode=>%s, p_city=>%s, p_country_code=>%s)",
                [
                    "Hélène",
                    "",
                    "Dubois-Lefèvre",
                    "1992-02-29",
                    "helene.dubois@example.fr",
                    "fr76 3000 6000 0112 3456 7890 189",
                    "12 rue des Lilas",
                    "69003",
                    "Lyon",
                    "fr",
                ],
                drop=(0,),
            ),
            C(
                "duplicate email differs only by case",
                "EXEC dbo.usp_policyholder_create @first_name=?, @last_name=?, @date_of_birth=?, @email=?, @iban=?, "
                "@address_line=?, @postcode=?, @city=?, @country_code=?",
                "SELECT * FROM {ns}.usp_policyholder_create(p_first_name=>%s, p_last_name=>%s, p_date_of_birth=>%s, "
                "p_email=>%s, p_iban=>%s, p_address_line=>%s, p_postcode=>%s, p_city=>%s, p_country_code=>%s)",
                ["Zoe", "Angstrom", "2000-02-29", "ZOE.ANGSTROM@example.com", "IE29AIBK93115212345678", "1 Main St", "D02", "Dublin", "IE"],
            ),
            C(
                "unknown country",
                "EXEC dbo.usp_policyholder_create @first_name=?, @last_name=?, @date_of_birth=?, @iban=?, "
                "@address_line=?, @postcode=?, @city=?, @country_code=?",
                "SELECT * FROM {ns}.usp_policyholder_create(p_first_name=>%s, p_last_name=>%s, p_date_of_birth=>%s, "
                "p_iban=>%s, p_address_line=>%s, p_postcode=>%s, p_city=>%s, p_country_code=>%s)",
                ["Ana", "Silva", "1980-05-05", "PT50000201231234567890154", "Rua 1", "1000-001", "Lisboa", "XX"],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT TOP (1) first_name, middle_name, last_name, full_name, email, iban, country_code FROM dbo.policyholder ORDER BY policyholder_id DESC",
                "SELECT first_name, middle_name, last_name, full_name, email, iban, country_code FROM {ns}.policyholder ORDER BY policyholder_id DESC LIMIT 1",
            )
        ],
    ),
    Control(
        "dbo.usp_policyholder_get",
        "procedure",
        "crud",
        1,
        "usp_policyholder_get",
        [
            C(
                "by email, different case",
                "EXEC dbo.usp_policyholder_get @email=?",
                "SELECT * FROM {ns}.usp_policyholder_get(p_email=>%s)",
                ["zoe.angstrom@EXAMPLE.COM"],
            ),
            C(
                "by id",
                "EXEC dbo.usp_policyholder_get @policyholder_id=?",
                "SELECT * FROM {ns}.usp_policyholder_get(p_policyholder_id=>%s)",
                [2],
            ),
        ],
    ),
    Control(
        "dbo.usp_policy_create",
        "procedure",
        "crud",
        1,
        "usp_policy_create",
        [
            C(
                "lower-case product and broker codes",
                "EXEC dbo.usp_policy_create @policyholder_id=?, @product_code=?, @broker_code=?, @inception_date=?, "
                "@payment_frequency=?, @sum_insured=?, @annual_premium=?, @as_of=?",
                "SELECT * FROM {ns}.usp_policy_create(p_policyholder_id=>%s, p_product_code=>%s, p_broker_code=>%s, "
                "p_inception_date=>%s, p_payment_frequency=>%s::smallint, p_sum_insured=>%s, p_annual_premium=>%s, p_as_of=>%s)",
                [8, "home-std", "brk-0007", "2024-02-29", 12, "85000", "289.0050", "2026-11-01 09:00:00"],
                drop=(0, 1),
            ),
            C(
                "unknown product",
                "EXEC dbo.usp_policy_create @policyholder_id=?, @product_code=?, @inception_date=?, @sum_insured=?, @annual_premium=?",
                "SELECT * FROM {ns}.usp_policy_create(p_policyholder_id=>%s, p_product_code=>%s, p_inception_date=>%s, "
                "p_sum_insured=>%s, p_annual_premium=>%s)",
                [8, "NOPE", "2026-01-01", "1000", "10"],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT TOP (2) p.status, p.expiry_date, p.annual_premium, v.version_no, v.effective_from, v.sum_insured, v.change_reason "
                "FROM dbo.policy p JOIN dbo.policy_version v ON v.policy_id = p.policy_id ORDER BY p.policy_id DESC, v.version_no",
                "SELECT p.status, p.expiry_date, p.annual_premium, v.version_no, v.effective_from, v.sum_insured, v.change_reason "
                "FROM {ns}.policy p JOIN {ns}.policy_version v ON v.policy_id = p.policy_id ORDER BY p.policy_id DESC, v.version_no LIMIT 2",
            )
        ],
    ),
    Control(
        "dbo.usp_policy_get",
        "procedure",
        "crud",
        1,
        "usp_policy_get",
        [
            C(
                "same-day correction is current",
                "EXEC dbo.usp_policy_get @policy_number=?",
                "SELECT * FROM {ns}.usp_policy_get(p_policy_number=>%s)",
                ["p000100001"],
            ),
            C(
                "mixed-case coverage codes",
                "EXEC dbo.usp_policy_get @policy_number=?",
                "SELECT * FROM {ns}.usp_policy_get(p_policy_number=>%s)",
                ["P000100097"],
            ),
        ],
    ),
    Control(
        "dbo.usp_policy_endorse",
        "procedure",
        "crud",
        1,
        "usp_policy_endorse",
        [
            C(
                "mid-term increase on an active policy",
                "EXEC dbo.usp_policy_endorse @policy_id=?, @effective_from=?, @sum_insured=?, @annual_premium=?, @change_reason=?, @as_of=?",
                "SELECT * FROM {ns}.usp_policy_endorse(p_policy_id=>%s, p_effective_from=>%s, p_sum_insured=>%s, "
                "p_annual_premium=>%s, p_change_reason=>%s, p_as_of=>%s)",
                [5, "2026-02-28", "14000", "101.0050", "Sum insured change", "2026-11-01 09:00:00"],
            ),
            C(
                "expired policy is rejected",
                "EXEC dbo.usp_policy_endorse @policy_id=?, @effective_from=?, @sum_insured=?, @annual_premium=?, @change_reason=?",
                "SELECT * FROM {ns}.usp_policy_endorse(p_policy_id=>%s, p_effective_from=>%s, p_sum_insured=>%s, "
                "p_annual_premium=>%s, p_change_reason=>%s)",
                [1, "2025-01-01", "1", "1", "x"],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium FROM dbo.policy_version WHERE policy_id = 5",
                "SELECT policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium FROM {ns}.policy_version WHERE policy_id = 5",
            ),
            (
                "SELECT policy_id, annual_premium, updated_at FROM dbo.policy WHERE policy_id = 5",
                "SELECT policy_id, annual_premium, updated_at FROM {ns}.policy WHERE policy_id = 5",
            ),
        ],
    ),
    Control(
        "dbo.usp_premium_payment_record",
        "procedure",
        "crud",
        1,
        "usp_premium_payment_record",
        [
            C(
                "allocate to installment, lower-case method",
                "EXEC dbo.usp_premium_payment_record @policy_id=?, @schedule_id=?, @amount=?, @method=?, @paid_at=?, @payer_iban=?",
                "SELECT * FROM {ns}.usp_premium_payment_record(p_policy_id=>%s, p_schedule_id=>%s, p_amount=>%s, "
                "p_method=>%s, p_paid_at=>%s, p_payer_iban=>%s)",
                [5, 48, "8.0625", "sepa_dd", "2026-11-01 10:15:00.123 +01:00", "DE89 3704 0044 0532 0130 00"],
            ),
            C(
                "negative amount rejected",
                "EXEC dbo.usp_premium_payment_record @policy_id=?, @amount=?, @method=?, @paid_at=?",
                "SELECT * FROM {ns}.usp_premium_payment_record(p_policy_id=>%s, p_amount=>%s, p_method=>%s, p_paid_at=>%s)",
                [5, "-1", "CARD", "2026-11-01 10:15:00 +01:00"],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT TOP (1) policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text FROM dbo.premium_payment ORDER BY payment_id DESC",
                "SELECT policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text FROM {ns}.premium_payment ORDER BY payment_id DESC LIMIT 1",
            ),
            (
                "SELECT schedule_id, paid_amount, status FROM dbo.premium_schedule WHERE schedule_id = 48",
                "SELECT schedule_id, paid_amount, status::text FROM {ns}.premium_schedule WHERE schedule_id = 48",
            ),
        ],
    ),
]

AS_OF = "2026-11-01 09:00:00"
POLICY_STATUS = (
    "SELECT status, COUNT(*) FROM dbo.policy GROUP BY status",
    "SELECT status::text, count(*) FROM {ns}.policy GROUP BY status",
)
SCHEDULE_STATUS = (
    "SELECT status, COUNT(*), SUM(amount_due) FROM dbo.premium_schedule GROUP BY status",
    "SELECT status::text, count(*), sum(amount_due) FROM {ns}.premium_schedule GROUP BY status",
)
BROKER_STATE = (
    "SELECT broker_id, commission_pct, is_active FROM dbo.broker",
    "SELECT broker_id, commission_pct, is_active FROM {ns}.broker",
)
RESERVES = (
    "SELECT claim_id, reserve_type, amount, set_by FROM dbo.claim_reserve WHERE claim_id IN (5, 15, 17)",
    "SELECT claim_id, reserve_type::text, amount, set_by FROM {ns}.claim_reserve WHERE claim_id IN (5, 15, 17)",
)


def P(name: str, category: str, cases: list[Case], **kw) -> Control:
    return Control(f"dbo.{name}", "procedure", category, 2, name, cases, **kw)


CONTROLS += [
    # ------------------------------------------------------------------- rating
    P(
        "usp_rate_quote",
        "rating",
        [
            C(
                "lower-case codes, 29 February birthday",
                "EXEC dbo.usp_rate_quote @product_code=?, @country_code=?, @sum_insured=?, @date_of_birth=?, @start_date=?",
                "SELECT * FROM {ns}.usp_rate_quote(p_product_code=>%s, p_country_code=>%s, p_sum_insured=>%s, "
                "p_date_of_birth=>%s, p_start_date=>%s)",
                ["motor-priv", "de", "25000", "2000-02-29", "2025-02-28"],
            ),
            C(
                "minimum premium applies",
                "EXEC dbo.usp_rate_quote @product_code=?, @country_code=?, @sum_insured=?, @date_of_birth=?, @start_date=?",
                "SELECT * FROM {ns}.usp_rate_quote(p_product_code=>%s, p_country_code=>%s, p_sum_insured=>%s, "
                "p_date_of_birth=>%s, p_start_date=>%s)",
                ["LIAB-PERS", "IT", "1000000", "1950-12-31", "2026-01-01"],
            ),
        ],
    ),
    P(
        "usp_premium_schedule_build",
        "rating",
        [
            C(
                "monthly plan, half-cent premium",
                "EXEC dbo.usp_premium_schedule_build @policy_id=?, @commit=?",
                "SELECT * FROM {ns}.usp_premium_schedule_build(p_policy_id=>%s, p_commit=>%s)",
                [53, True],
                ordered=True,
            ),
            C(
                "monthly plan",
                "EXEC dbo.usp_premium_schedule_build @policy_id=?, @commit=?",
                "SELECT * FROM {ns}.usp_premium_schedule_build(p_policy_id=>%s, p_commit=>%s)",
                [82, False],
                ordered=True,
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT policy_id, installment_no, due_date, amount_due, status FROM dbo.premium_schedule WHERE policy_id IN (53, 82)",
                "SELECT policy_id, installment_no, due_date, amount_due, status::text FROM {ns}.premium_schedule WHERE policy_id IN (53, 82)",
            )
        ],
    ),
    P(
        "usp_rate_renewal",
        "rating",
        [
            C(
                "36-month tenure boundary, same-day correction",
                "EXEC dbo.usp_rate_renewal @policy_id=?, @renewal_date=?",
                "SELECT * FROM {ns}.usp_rate_renewal(p_policy_id=>%s, p_renewal_date=>%s)",
                [3, "2026-03-01"],
            ),
            C(
                "recent claims loading",
                "EXEC dbo.usp_rate_renewal @policy_id=?, @renewal_date=?",
                "SELECT * FROM {ns}.usp_rate_renewal(p_policy_id=>%s, p_renewal_date=>%s)",
                [4, "2027-02-01"],
            ),
        ],
    ),
    # ------------------------------------------------------------------- claims
    P(
        "usp_claim_open",
        "claims",
        [
            C(
                "lower-case policy number, estimate above sum insured",
                "EXEC dbo.usp_claim_open @policy_number=?, @loss_date=?, @reported_at=?, @cause_code=?, @description=?, @initial_estimate=?",
                "SELECT * FROM {ns}.usp_claim_open(p_policy_number=>%s, p_loss_date=>%s, p_reported_at=>%s, "
                "p_cause_code=>%s, p_description=>%s, p_initial_estimate=>%s)",
                ["p000100001", "2024-12-31", "2025-01-02 08:30:00", "storm", "Roof tiles lost", "99999999"],
                drop=(0, 1),
            ),
            C(
                "loss outside cover",
                "EXEC dbo.usp_claim_open @policy_number=?, @loss_date=?, @reported_at=?, @initial_estimate=?",
                "SELECT * FROM {ns}.usp_claim_open(p_policy_number=>%s, p_loss_date=>%s, p_reported_at=>%s, p_initial_estimate=>%s)",
                ["P000100001", "2026-01-01", "2026-01-02 08:00:00", "100"],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT TOP (1) c.policy_id, c.loss_date, c.cause_code, c.status, r.reserve_type, r.amount FROM dbo.claim c "
                "JOIN dbo.claim_reserve r ON r.claim_id = c.claim_id ORDER BY c.claim_id DESC, r.reserve_type",
                "SELECT c.policy_id, c.loss_date, c.cause_code::text, c.status::text, r.reserve_type::text, r.amount FROM {ns}.claim c "
                "JOIN {ns}.claim_reserve r ON r.claim_id = c.claim_id ORDER BY c.claim_id DESC, r.reserve_type LIMIT 1",
            )
        ],
    ),
    P(
        "usp_claim_reserve_set",
        "claims",
        [
            C(
                "new expense reserve (insert branch)",
                "EXEC dbo.usp_claim_reserve_set @claim_id=?, @reserve_type=?, @amount=?, @set_by=?, @as_of=?",
                "SELECT * FROM {ns}.usp_claim_reserve_set(p_claim_id=>%s, p_reserve_type=>%s, p_amount=>%s, p_set_by=>%s, p_as_of=>%s)",
                [5, "expense", "50.00", "adjuster.42", AS_OF],
            ),
            C(
                "reserve below paid, lower-case type",
                "EXEC dbo.usp_claim_reserve_set @claim_id=?, @reserve_type=?, @amount=?, @set_by=?, @as_of=?",
                "SELECT * FROM {ns}.usp_claim_reserve_set(p_claim_id=>%s, p_reserve_type=>%s, p_amount=>%s, p_set_by=>%s, p_as_of=>%s)",
                [15, "indemnity", "100.00", "adjuster.42", AS_OF],
            ),
            C(
                "increase indemnity (update branch)",
                "EXEC dbo.usp_claim_reserve_set @claim_id=?, @reserve_type=?, @amount=?, @set_by=?, @as_of=?",
                "SELECT * FROM {ns}.usp_claim_reserve_set(p_claim_id=>%s, p_reserve_type=>%s, p_amount=>%s, p_set_by=>%s, p_as_of=>%s)",
                [17, "INDEMNITY", "700.0050", "adjuster.42", AS_OF],
            ),
        ],
        writes=True,
        state=[RESERVES],
    ),
    P(
        "usp_claim_payment_record",
        "claims",
        [
            C(
                "half-cent payment, mixed-case type",
                "EXEC dbo.usp_claim_payment_record @claim_id=?, @reserve_type=?, @amount=?, @payee_name=?, @paid_at=?",
                "SELECT * FROM {ns}.usp_claim_payment_record(p_claim_id=>%s, p_reserve_type=>%s, p_amount=>%s, "
                "p_payee_name=>%s, p_paid_at=>%s)",
                [5, "Indemnity", "100.005", "Dachdeckerei Groß", AS_OF],
            ),
            C(
                "payment above reserve",
                "EXEC dbo.usp_claim_payment_record @claim_id=?, @reserve_type=?, @amount=?, @payee_name=?, @paid_at=?",
                "SELECT * FROM {ns}.usp_claim_payment_record(p_claim_id=>%s, p_reserve_type=>%s, p_amount=>%s, "
                "p_payee_name=>%s, p_paid_at=>%s)",
                [5, "INDEMNITY", "100000", "X", AS_OF],
            ),
        ],
        writes=True,
        state=[
            (
                "SELECT TOP (1) claim_id, reserve_type, amount, payee_name FROM dbo.claim_payment ORDER BY claim_payment_id DESC",
                "SELECT claim_id, reserve_type::text, amount, payee_name FROM {ns}.claim_payment ORDER BY claim_payment_id DESC LIMIT 1",
            ),
            AUDIT_TAIL,
        ],
    ),
    P(
        "usp_claim_close",
        "claims",
        [
            C(
                "close and release reserve",
                "EXEC dbo.usp_claim_close @claim_id=?, @as_of=?",
                "SELECT * FROM {ns}.usp_claim_close(p_claim_id=>%s, p_as_of=>%s)",
                [5, AS_OF],
            ),
            C(
                "already closed",
                "EXEC dbo.usp_claim_close @claim_id=?, @as_of=?",
                "SELECT * FROM {ns}.usp_claim_close(p_claim_id=>%s, p_as_of=>%s)",
                [2, AS_OF],
            ),
        ],
        writes=True,
        state=[RESERVES, AUDIT_TAIL],
    ),
    # ---------------------------------------------------------------- reporting
    P(
        "usp_report_loss_ratio",
        "reporting",
        [
            C(
                "calendar 2025",
                "EXEC dbo.usp_report_loss_ratio @from_date=?, @to_date=?",
                "SELECT * FROM {ns}.usp_report_loss_ratio(p_from_date=>%s, p_to_date=>%s)",
                ["2025-01-01", "2025-12-31"],
            ),
            C(
                "H1 2026",
                "EXEC dbo.usp_report_loss_ratio @from_date=?, @to_date=?",
                "SELECT * FROM {ns}.usp_report_loss_ratio(p_from_date=>%s, p_to_date=>%s)",
                ["2026-01-01", "2026-06-30"],
            ),
        ],
    ),
    P(
        "usp_report_claims_ageing",
        "reporting",
        [
            C(
                "as of 1 April 2026 (month-end losses)",
                "EXEC dbo.usp_report_claims_ageing @as_of=?",
                "SELECT * FROM {ns}.usp_report_claims_ageing(p_as_of=>%s)",
                ["2026-04-01"],
            ),
            C(
                "as of 31 October 2026",
                "EXEC dbo.usp_report_claims_ageing @as_of=?",
                "SELECT * FROM {ns}.usp_report_claims_ageing(p_as_of=>%s)",
                ["2026-10-31"],
            ),
        ],
    ),
    P(
        "usp_report_broker_production",
        "reporting",
        [
            C(
                "top 5 in 'de' (lower case)",
                "EXEC dbo.usp_report_broker_production @country_code=?, @top_n=?",
                "SELECT * FROM {ns}.usp_report_broker_production(p_country_code=>%s, p_top_n=>%s)",
                ["de", 5],
            ),
            C(
                "top 3 motor, all countries",
                "EXEC dbo.usp_report_broker_production @line_of_business=?, @top_n=?",
                "SELECT * FROM {ns}.usp_report_broker_production(p_line_of_business=>%s, p_top_n=>%s)",
                ["motor", 3],
            ),
        ],
    ),
    P(
        "usp_report_policy_json",
        "reporting",
        [
            C(
                "no broker, no e-mail",
                "EXEC dbo.usp_report_policy_json @policy_number=?",
                "SELECT * FROM {ns}.usp_report_policy_json(p_policy_number=>%s)",
                ["P000100033"],
                json_cols=(0,),
            ),
            C(
                "mixed-case coverage",
                "EXEC dbo.usp_report_policy_json @policy_number=?",
                "SELECT * FROM {ns}.usp_report_policy_json(p_policy_number=>%s)",
                ["p000100097"],
                json_cols=(0,),
            ),
        ],
    ),
    # -------------------------------------------------------------------- batch
    P(
        "usp_batch_mark_overdue",
        "batch",
        [
            C(
                "run 2026-11-01",
                "EXEC dbo.usp_batch_mark_overdue @run_date=?",
                "SELECT * FROM {ns}.usp_batch_mark_overdue(p_run_date=>%s)",
                ["2026-11-01"],
            ),
        ],
        writes=True,
        state=[SCHEDULE_STATUS],
    ),
    P(
        "usp_batch_lapse_overdue",
        "batch",
        [
            C(
                "run 2026-11-01",
                "EXEC dbo.usp_batch_lapse_overdue @run_date=?",
                "SELECT * FROM {ns}.usp_batch_lapse_overdue(p_run_date=>%s)",
                ["2026-11-01"],
            ),
        ],
        writes=True,
        state=[
            POLICY_STATUS,
            SCHEDULE_STATUS,
            (
                "SELECT action, old_value, new_value, row_count, COUNT(*) FROM dbo.audit_log GROUP BY action, old_value, new_value, row_count",
                "SELECT action, old_value, new_value, row_count, count(*) FROM {ns}.audit_log GROUP BY action, old_value, new_value, row_count",
            ),
        ],
    ),
    P(
        "usp_batch_sync_broker_commission",
        "batch",
        [
            C(
                "run 2026-11-01",
                "EXEC dbo.usp_batch_sync_broker_commission @run_date=?",
                "SELECT * FROM {ns}.usp_batch_sync_broker_commission(p_run_date=>%s)",
                ["2026-11-01"],
            ),
        ],
        writes=True,
        state=[BROKER_STATE],
    ),
    P(
        "usp_batch_nightly",
        "batch",
        [
            C(
                "run 2026-11-01",
                "EXEC dbo.usp_batch_nightly @run_date=?",
                "SELECT * FROM {ns}.usp_batch_nightly(p_run_date=>%s)",
                ["2026-11-01"],
            ),
        ],
        writes=True,
        state=[POLICY_STATUS, SCHEDULE_STATUS, BROKER_STATE],
    ),
    # ----------------------------------------------------------------- triggers
    Control(
        "dbo.trg_policy_status_audit",
        "trigger",
        "trigger",
        2,
        "trg_policy_status_audit",
        [
            C(
                "multi-row status update",
                "UPDATE dbo.policy SET status = 'CANCELLED' WHERE policy_id IN (5, 6, 7, 8)",
                "UPDATE {ns}.policy SET status = 'CANCELLED' WHERE policy_id IN (5, 6, 7, 8)",
            ),
        ],
        writes=True,
        state=[AUDIT_TAIL],
    ),
    Control(
        "dbo.trg_claim_status_audit",
        "trigger",
        "trigger",
        2,
        "trg_claim_status_audit",
        [
            C(
                "reopen two claims, one unchanged",
                "UPDATE dbo.claim SET status = IIF(claim_id = 3, status, 'REOPENED') WHERE claim_id IN (2, 3, 4)",
                "UPDATE {ns}.claim SET status = CASE WHEN claim_id = 3 THEN status ELSE 'REOPENED' END WHERE claim_id IN (2, 3, 4)",
            ),
        ],
        writes=True,
        state=[AUDIT_TAIL],
    ),
    Control(
        "dbo.trg_claim_payment_audit",
        "trigger",
        "trigger",
        2,
        "trg_claim_payment_audit",
        [
            C(
                "two payments in one statement",
                "INSERT INTO dbo.claim_payment (claim_id, reserve_type, paid_at, amount, payee_name) "
                "VALUES (15, 'INDEMNITY', '2026-11-01', 10.50, N'A'), (17, 'INDEMNITY', '2026-11-01', 20.25, N'B')",
                "INSERT INTO {ns}.claim_payment (claim_id, reserve_type, paid_at, amount, payee_name) "
                "VALUES (15, 'INDEMNITY', '2026-11-01', 10.50, 'A'), (17, 'INDEMNITY', '2026-11-01', 20.25, 'B')",
            ),
        ],
        writes=True,
        state=[AUDIT_TAIL],
    ),
]

# Business-rule controls: each must hold on both engines and agree.
BUSINESS_RULES = [
    (
        "premium schedule adds up to the annual premium (violations)",
        "SELECT COUNT(*) FROM (SELECT p.policy_id FROM dbo.policy p JOIN dbo.premium_schedule s ON s.policy_id = p.policy_id "
        "GROUP BY p.policy_id, p.annual_premium HAVING SUM(s.amount_due) <> p.annual_premium) x",
        "SELECT count(*) FROM (SELECT p.policy_id FROM {ns}.policy p JOIN {ns}.premium_schedule s ON s.policy_id = p.policy_id "
        "GROUP BY p.policy_id, p.annual_premium HAVING sum(s.amount_due) <> p.annual_premium) x",
        True,
    ),
    (
        "claim reserve >= paid per reserve type (violations)",
        "SELECT COUNT(*) FROM dbo.claim_reserve r CROSS APPLY (SELECT SUM(amount) AS paid FROM dbo.claim_payment cp "
        "WHERE cp.claim_id = r.claim_id AND cp.reserve_type = r.reserve_type) p WHERE p.paid > r.amount",
        "SELECT count(*) FROM {ns}.claim_reserve r CROSS JOIN LATERAL (SELECT sum(amount) AS paid FROM {ns}.claim_payment cp "
        "WHERE cp.claim_id = r.claim_id AND cp.reserve_type = r.reserve_type) p WHERE p.paid > r.amount",
        True,
    ),
    (
        "loss ratio by product (paid / collected, 4 dp)",
        "SELECT pr.product_code, CAST(ROUND(ISNULL(c.paid, 0) / NULLIF(m.collected, 0), 4) AS DECIMAL(19, 4)) FROM ref.product pr "
        "OUTER APPLY (SELECT SUM(pp.amount) AS collected FROM dbo.premium_payment pp JOIN dbo.policy p ON p.policy_id = pp.policy_id "
        "WHERE p.product_id = pr.product_id) m OUTER APPLY (SELECT CAST(SUM(cp.amount) AS DECIMAL(19, 4)) AS paid FROM dbo.claim_payment cp "
        "JOIN dbo.claim c ON c.claim_id = cp.claim_id JOIN dbo.policy p ON p.policy_id = c.policy_id WHERE p.product_id = pr.product_id) c",
        "SELECT pr.product_code::text, round(coalesce(c.paid, 0) / nullif(m.collected, 0), 4) FROM {ns}.product pr "
        "LEFT JOIN LATERAL (SELECT sum(pp.amount) AS collected FROM {ns}.premium_payment pp JOIN {ns}.policy p ON p.policy_id = pp.policy_id "
        "WHERE p.product_id = pr.product_id) m ON true LEFT JOIN LATERAL (SELECT sum(cp.amount) AS paid FROM {ns}.claim_payment cp "
        "JOIN {ns}.claim c ON c.claim_id = cp.claim_id JOIN {ns}.policy p ON p.policy_id = c.policy_id WHERE p.product_id = pr.product_id) c ON true",
        False,
    ),
    (
        "premium collected by year (control totals)",
        "SELECT YEAR(SWITCHOFFSET(paid_at, '+00:00')), COUNT(*), SUM(amount) FROM dbo.premium_payment GROUP BY YEAR(SWITCHOFFSET(paid_at, '+00:00'))",
        "SELECT extract(YEAR FROM paid_at AT TIME ZONE 'UTC')::int, count(*), sum(amount) FROM {ns}.premium_payment GROUP BY 1",
        False,
    ),
]
