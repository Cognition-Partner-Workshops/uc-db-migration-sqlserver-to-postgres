-- dbo.usp_report_claims_ageing. Bands count month boundaries like
-- DATEDIFF(MONTH) (fn_months_between), not age(). ISNULL takes the type of its
-- first argument, so the fallback is cut to cause_code's varchar(10).
CREATE FUNCTION $(NS).usp_report_claims_ageing(p_as_of date)
RETURNS TABLE (cause_code text, age_band text, open_claims bigint, outstanding numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT
        upper(coalesce(c.cause_code::text, left('UNSPECIFIED', 10))) AS cause_code,
        band.age_band,
        count(*) AS open_claims,
        sum(coalesce(r.reserve_total, 0) - coalesce(p.paid_total, 0)) AS outstanding
    FROM $(NS).claim AS c
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN $(NS).fn_months_between(c.loss_date, p_as_of) < 3 THEN '0-2m'
            WHEN $(NS).fn_months_between(c.loss_date, p_as_of) < 6 THEN '3-5m'
            WHEN $(NS).fn_months_between(c.loss_date, p_as_of) < 12 THEN '6-11m'
            ELSE '12m+'
        END AS age_band
    ) AS band
    LEFT JOIN LATERAL (
        SELECT sum(cr.amount) AS reserve_total FROM $(NS).claim_reserve AS cr WHERE cr.claim_id = c.claim_id
    ) AS r ON true
    LEFT JOIN LATERAL (
        SELECT sum(cp.amount) AS paid_total FROM $(NS).claim_payment AS cp WHERE cp.claim_id = c.claim_id
    ) AS p ON true
    WHERE c.status IN ('OPEN', 'REOPENED') AND c.loss_date <= p_as_of
    GROUP BY 1, 2
    ORDER BY 1, 2
$$;
