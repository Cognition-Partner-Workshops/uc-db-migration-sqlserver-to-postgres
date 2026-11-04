-- A plausible, line-by-line conversion of dbo.usp_report_claims_ageing, the
-- kind a quick rewrite (or a tool) produces. Deployed only by
-- `make reconcile-naive`; it is meant to fail reconciliation.
CREATE FUNCTION $(NS).usp_report_claims_ageing(p_as_of date)
RETURNS TABLE (cause_code text, age_band text, open_claims bigint, outstanding numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT
        upper(coalesce(c.cause_code::text, 'UNSPECIFIED')) AS cause_code,
        band.age_band,
        count(*) AS open_claims,
        sum(coalesce(r.reserve_total, 0) - coalesce(p.paid_total, 0)) AS outstanding
    FROM $(NS).claim AS c
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN extract(YEAR FROM age(p_as_of, c.loss_date)) * 12
                + extract(MONTH FROM age(p_as_of, c.loss_date)) < 3 THEN '0-2m'
            WHEN extract(YEAR FROM age(p_as_of, c.loss_date)) * 12
                + extract(MONTH FROM age(p_as_of, c.loss_date)) < 6 THEN '3-5m'
            WHEN extract(YEAR FROM age(p_as_of, c.loss_date)) * 12
                + extract(MONTH FROM age(p_as_of, c.loss_date)) < 12 THEN '6-11m'
            ELSE '12m+'
        END AS age_band
    ) AS band
    LEFT JOIN LATERAL (
        SELECT sum(cr.amount) AS reserve_total
        FROM $(NS).claim_reserve AS cr
        WHERE cr.claim_id = c.claim_id
    ) AS r ON true
    LEFT JOIN LATERAL (
        SELECT sum(cp.amount) AS paid_total
        FROM $(NS).claim_payment AS cp
        WHERE cp.claim_id = c.claim_id
    ) AS p ON true
    WHERE c.status IN ('OPEN', 'REOPENED') AND c.loss_date <= p_as_of
    GROUP BY 1, 2
    ORDER BY 1, 2
$$;
