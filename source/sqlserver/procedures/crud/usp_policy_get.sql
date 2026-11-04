-- Policy detail screen: header, current version and coverage summary.
CREATE OR ALTER PROCEDURE dbo.usp_policy_get
    @policy_number VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.policy_id,
        p.policy_number,
        p.status,
        pr.product_code,
        pr.product_name,
        dbo.fn_format_name(ph.first_name, ph.middle_name, ph.last_name) AS holder_name,
        COALESCE(b.broker_name, N'Direct') AS broker_name,
        p.inception_date,
        p.expiry_date,
        cv.version_no,
        cv.sum_insured,
        cv.annual_premium,
        cs.coverage_count,
        cs.total_limit,
        cs.coverage_codes
    FROM dbo.policy AS p
    INNER JOIN ref.product AS pr ON pr.product_id = p.product_id
    INNER JOIN dbo.policyholder AS ph ON ph.policyholder_id = p.policyholder_id
    LEFT JOIN dbo.broker AS b ON b.broker_id = p.broker_id
    OUTER APPLY (
        SELECT TOP (1) v.version_no, v.sum_insured, v.annual_premium
        FROM dbo.policy_version AS v
        WHERE v.policy_id = p.policy_id
        ORDER BY v.effective_from DESC, v.version_no DESC
    ) AS cv
    OUTER APPLY dbo.tvf_policy_coverage_summary(p.policy_id) AS cs
    WHERE p.policy_number = @policy_number;
END;
GO
