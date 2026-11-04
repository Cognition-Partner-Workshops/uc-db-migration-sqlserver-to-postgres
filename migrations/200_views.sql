CREATE VIEW $(NS).vw_active_policy AS
SELECT
    p.policy_id,
    p.policy_number,
    pr.product_code,
    pr.line_of_business,
    $(NS).fn_format_name(ph.first_name, ph.middle_name, ph.last_name) AS holder_name,
    ph.country_code AS holder_country,
    coalesce(b.broker_code, 'DIRECT') AS broker_code,
    p.inception_date,
    p.expiry_date,
    cv.version_no AS current_version,
    cv.sum_insured,
    cv.annual_premium AS current_premium,
    CASE WHEN p.payment_frequency = 1 THEN 'ANNUAL' ELSE 'INSTALMENTS' END AS billing_mode
FROM $(NS).policy AS p
INNER JOIN $(NS).product AS pr ON p.product_id = pr.product_id
INNER JOIN $(NS).policyholder AS ph ON p.policyholder_id = ph.policyholder_id
LEFT JOIN $(NS).broker AS b ON p.broker_id = b.broker_id
LEFT JOIN LATERAL (
    SELECT
        v.version_no,
        v.sum_insured,
        v.annual_premium
    FROM $(NS).policy_version AS v
    WHERE v.policy_id = p.policy_id
    ORDER BY v.effective_from DESC, v.version_no DESC
    LIMIT 1
) AS cv ON true
WHERE p.status = 'ACTIVE';

CREATE VIEW $(NS).vw_claim_position AS
SELECT
    c.claim_id,
    c.claim_number,
    c.policy_id,
    c.status,
    c.loss_date,
    coalesce(r.reserve_total, 0) AS reserve_total,
    coalesce(pay.paid_total, 0) AS paid_total,
    coalesce(r.reserve_total, 0) - coalesce(pay.paid_total, 0) AS outstanding,
    pay.last_paid_at
FROM $(NS).claim AS c
LEFT JOIN LATERAL (
    SELECT sum(cr.amount) AS reserve_total
    FROM $(NS).claim_reserve AS cr
    WHERE cr.claim_id = c.claim_id
) AS r ON true
LEFT JOIN LATERAL (
    SELECT
        sum(cp.amount) AS paid_total,
        max(cp.paid_at) AS last_paid_at
    FROM $(NS).claim_payment AS cp
    WHERE cp.claim_id = c.claim_id
) AS pay ON true;

-- PIVOT -> conditional aggregation. coverage_code is citext, so the
-- comparisons stay case-insensitive like the legacy IN ([TPL], ...) list.
CREATE VIEW $(NS).vw_policy_coverage_pivot AS
SELECT
    c.policy_id,
    sum(c.limit_amount) FILTER (WHERE c.coverage_code = 'TPL') AS tpl_limit,
    sum(c.limit_amount) FILTER (WHERE c.coverage_code = 'FIRE') AS fire_limit,
    sum(c.limit_amount) FILTER (WHERE c.coverage_code = 'THEFT') AS theft_limit,
    sum(c.limit_amount) FILTER (WHERE c.coverage_code = 'GLASS') AS glass_limit,
    sum(c.limit_amount) FILTER (WHERE c.coverage_code = 'FLOOD') AS flood_limit
FROM $(NS).coverage AS c
GROUP BY c.policy_id;

CREATE VIEW $(NS).vw_broker_portfolio AS
SELECT
    b.broker_id,
    b.broker_code,
    b.broker_name,
    b.country_code,
    count(p.policy_id) AS live_policies,
    coalesce(sum(p.annual_premium), 0) AS gross_written_premium,
    coalesce(sum(p.annual_premium), 0) * b.commission_pct / 100 AS expected_commission,
    (
        SELECT string_agg(x.product_code::text, ',' ORDER BY x.product_code)
        FROM (
            SELECT DISTINCT pr.product_code
            FROM $(NS).policy AS p2
            INNER JOIN $(NS).product AS pr ON p2.product_id = pr.product_id
            WHERE p2.broker_id = b.broker_id AND p2.status = 'ACTIVE'
        ) AS x
    ) AS products_sold
FROM $(NS).broker AS b
LEFT JOIN $(NS).policy AS p ON b.broker_id = p.broker_id AND p.status = 'ACTIVE'
GROUP BY b.broker_id, b.broker_code, b.broker_name, b.country_code, b.commission_pct;
