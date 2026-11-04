-- Load the namespace from the raw landing copy, then move identities and
-- sequences past the loaded keys.
INSERT INTO $(NS).country SELECT country_code, country_name, currency_code, is_eu_member, premium_tax_rate
FROM raw.ref_country;

INSERT INTO $(NS).product (product_id, product_code, product_name, line_of_business, base_rate, min_premium, is_active)
SELECT product_id, product_code, product_name, line_of_business, base_rate, min_premium, is_active
FROM raw.ref_product;

INSERT INTO $(NS).broker (
    broker_id, broker_code, broker_name, country_code, commission_pct, email, is_active, created_at
)
SELECT broker_id, broker_code, broker_name, country_code, commission_pct, email, is_active, created_at
FROM raw.dbo_broker;

INSERT INTO $(NS).policyholder (
    policyholder_id, external_ref, first_name, middle_name, last_name, date_of_birth, email, phone,
    iban, address_line, postcode, city, country_code, created_at
)
SELECT
    policyholder_id, external_ref, first_name, middle_name, last_name, date_of_birth, email, phone,
    iban, address_line, postcode, city, country_code, created_at
FROM raw.dbo_policyholder;

INSERT INTO $(NS).policy (
    policy_id, policy_number, policyholder_id, broker_id, product_id, status, inception_date, expiry_date,
    payment_frequency, annual_premium, currency_code, created_at, updated_at
)
SELECT
    policy_id, policy_number, policyholder_id, broker_id, product_id, status, inception_date, expiry_date,
    payment_frequency, annual_premium, currency_code, created_at, updated_at
FROM raw.dbo_policy;

INSERT INTO $(NS).policy_version (
    policy_version_id, policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium,
    change_reason, created_at
)
SELECT
    policy_version_id, policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium,
    change_reason, created_at
FROM raw.dbo_policy_version;

INSERT INTO $(NS).coverage (coverage_id, policy_id, coverage_code, limit_amount, deductible, premium_share)
SELECT coverage_id, policy_id, coverage_code, limit_amount, deductible, premium_share
FROM raw.dbo_coverage;

INSERT INTO $(NS).premium_schedule (
    schedule_id, policy_id, installment_no, due_date, amount_due, paid_amount, status
)
SELECT schedule_id, policy_id, installment_no, due_date, amount_due, paid_amount, status
FROM raw.dbo_premium_schedule;

INSERT INTO $(NS).premium_payment (
    payment_id, payment_ref, policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text
)
SELECT payment_id, payment_ref, policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text
FROM raw.dbo_premium_payment;

INSERT INTO $(NS).claim (
    claim_id, claim_number, policy_id, loss_date, reported_at, cause_code, status, description, closed_at
)
SELECT claim_id, claim_number, policy_id, loss_date, reported_at, cause_code, status, description, closed_at
FROM raw.dbo_claim;

INSERT INTO $(NS).claim_reserve (reserve_id, claim_id, reserve_type, amount, set_at, set_by)
SELECT reserve_id, claim_id, reserve_type, amount, set_at, set_by
FROM raw.dbo_claim_reserve;

INSERT INTO $(NS).claim_payment (
    claim_payment_id, claim_id, reserve_type, paid_at, amount, payee_name, payee_iban
)
SELECT claim_payment_id, claim_id, reserve_type, paid_at, amount, payee_name, payee_iban
FROM raw.dbo_claim_payment;

INSERT INTO $(NS).audit_log (
    audit_id, table_name, action, key_value, old_value, new_value, row_count, changed_at, changed_by
)
SELECT audit_id, table_name, action, key_value, old_value, new_value, row_count, changed_at, changed_by
FROM raw.dbo_audit_log;

SELECT $(NS).reset_identities();
