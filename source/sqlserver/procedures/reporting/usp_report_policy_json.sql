-- Policy document as JSON for the customer portal.
CREATE OR ALTER PROCEDURE dbo.usp_report_policy_json
    @policy_number VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT (
        SELECT
            p.policy_number AS [policyNumber],
            p.status AS [status],
            p.inception_date AS [inceptionDate],
            p.annual_premium AS [annualPremium],
            pr.product_code AS [product.code],
            pr.product_name AS [product.name],
            ph.full_name AS [holder.name],
            ph.email AS [holder.email],
            b.broker_code AS [broker.code],
            (
                SELECT
                    c.coverage_code AS [code],
                    c.limit_amount AS [limit],
                    c.deductible AS [deductible]
                FROM dbo.coverage AS c
                WHERE c.policy_id = p.policy_id
                ORDER BY c.coverage_code, c.coverage_id
                FOR JSON PATH
            ) AS [coverages]
        FROM dbo.policy AS p
        INNER JOIN ref.product AS pr ON pr.product_id = p.product_id
        INNER JOIN dbo.policyholder AS ph ON ph.policyholder_id = p.policyholder_id
        LEFT JOIN dbo.broker AS b ON b.broker_id = p.broker_id
        WHERE p.policy_number = @policy_number
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS policy_json;
END;
GO
