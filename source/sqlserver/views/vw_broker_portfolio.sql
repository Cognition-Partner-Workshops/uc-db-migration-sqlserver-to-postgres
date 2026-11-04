-- Broker book: live policies, gross written premium and products sold.
CREATE OR ALTER VIEW dbo.vw_broker_portfolio
AS
SELECT
    b.broker_id,
    b.broker_code,
    b.broker_name,
    b.country_code,
    COUNT(p.policy_id) AS live_policies,
    COALESCE(SUM(p.annual_premium), 0) AS gross_written_premium,
    COALESCE(SUM(p.annual_premium), 0) * b.commission_pct / 100 AS expected_commission,
    (
        SELECT STRING_AGG(x.product_code, ',') WITHIN GROUP (ORDER BY x.product_code)
        FROM (
            SELECT DISTINCT pr.product_code
            FROM dbo.policy AS p2
            INNER JOIN ref.product AS pr ON pr.product_id = p2.product_id
            WHERE p2.broker_id = b.broker_id AND p2.status = 'ACTIVE'
        ) AS x
    ) AS products_sold
FROM dbo.broker AS b
LEFT JOIN dbo.policy AS p ON p.broker_id = b.broker_id AND p.status = 'ACTIVE'
GROUP BY b.broker_id, b.broker_code, b.broker_name, b.country_code, b.commission_pct;
GO
