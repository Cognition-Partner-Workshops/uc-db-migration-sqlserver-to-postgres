-- Open claims by cause and age band (months since loss).
CREATE OR ALTER PROCEDURE dbo.usp_report_claims_ageing
    @as_of DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        UPPER(ISNULL(c.cause_code, 'UNSPECIFIED')) AS cause_code,
        band.age_band,
        COUNT(*) AS open_claims,
        SUM(ISNULL(r.reserve_total, 0) - ISNULL(p.paid_total, 0)) AS outstanding
    FROM dbo.claim AS c
    CROSS APPLY (
        SELECT CASE
            WHEN DATEDIFF(MONTH, c.loss_date, @as_of) < 3 THEN '0-2m'
            WHEN DATEDIFF(MONTH, c.loss_date, @as_of) < 6 THEN '3-5m'
            WHEN DATEDIFF(MONTH, c.loss_date, @as_of) < 12 THEN '6-11m'
            ELSE '12m+'
        END AS age_band
    ) AS band
    OUTER APPLY (
        SELECT SUM(cr.amount) AS reserve_total
        FROM dbo.claim_reserve AS cr
        WHERE cr.claim_id = c.claim_id
    ) AS r
    OUTER APPLY (
        SELECT SUM(cp.amount) AS paid_total
        FROM dbo.claim_payment AS cp
        WHERE cp.claim_id = c.claim_id
    ) AS p
    WHERE c.status IN ('OPEN', 'REOPENED') AND c.loss_date <= @as_of
    GROUP BY UPPER(ISNULL(c.cause_code, 'UNSPECIFIED')), band.age_band
    ORDER BY cause_code, band.age_band;
END;
GO
