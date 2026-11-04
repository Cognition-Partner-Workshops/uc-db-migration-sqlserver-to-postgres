-- Inline TVF: one summary row of a policy's coverages.
CREATE OR ALTER FUNCTION dbo.tvf_policy_coverage_summary (@policy_id INT)
RETURNS TABLE
AS
RETURN
(
    SELECT
        c.policy_id,
        COUNT(*) AS coverage_count,
        SUM(c.limit_amount) AS total_limit,
        SUM(c.deductible) AS total_deductible,
        STRING_AGG(UPPER(c.coverage_code), ',') WITHIN GROUP (ORDER BY UPPER(c.coverage_code)) AS coverage_codes
    FROM dbo.coverage AS c
    WHERE c.policy_id = @policy_id
    GROUP BY c.policy_id
);
GO
