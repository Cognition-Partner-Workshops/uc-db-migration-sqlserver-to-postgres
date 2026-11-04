-- Loss ratio per product for a period: paid claims over collected premium.
CREATE OR ALTER PROCEDURE dbo.usp_report_loss_ratio
    @from_date DATE,
    @to_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #earned (
        product_id INT NOT NULL PRIMARY KEY,
        premium_cents BIGINT NOT NULL,
        policy_count INT NOT NULL
    );

    CREATE TABLE #incurred (
        product_id INT NOT NULL PRIMARY KEY,
        paid_cents BIGINT NOT NULL,
        claim_count INT NOT NULL,
        avg_report_lag_days INT NULL
    );

    INSERT INTO #earned (product_id, premium_cents, policy_count)
    SELECT
        p.product_id,
        CAST(ROUND(SUM(pp.amount) * 100, 0) AS BIGINT),
        COUNT(DISTINCT p.policy_id)
    FROM dbo.premium_payment AS pp
    INNER JOIN dbo.policy AS p ON p.policy_id = pp.policy_id
    WHERE pp.paid_at >= CAST(@from_date AS DATETIMEOFFSET(3))
        AND pp.paid_at < CAST(DATEADD(DAY, 1, @to_date) AS DATETIMEOFFSET(3))
    GROUP BY p.product_id;

    INSERT INTO #incurred (product_id, paid_cents, claim_count, avg_report_lag_days)
    SELECT
        p.product_id,
        CAST(ROUND(ISNULL(SUM(cp.paid), 0) * 100, 0) AS BIGINT),
        COUNT(*),
        AVG(DATEDIFF(DAY, c.loss_date, c.reported_at))
    FROM dbo.claim AS c
    INNER JOIN dbo.policy AS p ON p.policy_id = c.policy_id
    OUTER APPLY (
        SELECT SUM(x.amount) AS paid
        FROM dbo.claim_payment AS x
        WHERE x.claim_id = c.claim_id
    ) AS cp
    WHERE c.loss_date BETWEEN @from_date AND @to_date
        AND c.status <> 'DENIED'
    GROUP BY p.product_id;

    SELECT
        pr.product_code,
        pr.line_of_business,
        e.policy_count,
        ISNULL(i.claim_count, 0) AS claim_count,
        CAST(e.premium_cents AS DECIMAL(19, 2)) / 100 AS earned_premium,
        CAST(ISNULL(i.paid_cents, 0) AS DECIMAL(19, 2)) / 100 AS paid_claims,
        ISNULL(i.paid_cents, 0) * 100 / NULLIF(e.premium_cents, 0) AS loss_ratio_pct,
        ISNULL(i.claim_count, 0) * 100 / e.policy_count AS claims_per_100_policies,
        i.avg_report_lag_days
    FROM #earned AS e
    INNER JOIN ref.product AS pr ON pr.product_id = e.product_id
    LEFT JOIN #incurred AS i ON i.product_id = e.product_id
    ORDER BY pr.product_code;
END;
GO
