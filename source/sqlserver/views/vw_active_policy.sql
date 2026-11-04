-- Active policies with their current version, product, holder and broker.
CREATE OR ALTER VIEW dbo.vw_active_policy
AS
SELECT
    p.policy_id,
    p.policy_number,
    pr.product_code,
    pr.line_of_business,
    dbo.fn_format_name(ph.first_name, ph.middle_name, ph.last_name) AS holder_name,
    ph.country_code AS holder_country,
    ISNULL(b.broker_code, 'DIRECT') AS broker_code,
    p.inception_date,
    p.expiry_date,
    cv.version_no AS current_version,
    cv.sum_insured,
    cv.annual_premium AS current_premium,
    IIF(p.payment_frequency = 1, 'ANNUAL', 'INSTALMENTS') AS billing_mode
FROM dbo.policy AS p
INNER JOIN ref.product AS pr ON pr.product_id = p.product_id
INNER JOIN dbo.policyholder AS ph ON ph.policyholder_id = p.policyholder_id
LEFT JOIN dbo.broker AS b ON b.broker_id = p.broker_id
OUTER APPLY (
    SELECT TOP (1)
        v.version_no,
        v.sum_insured,
        v.annual_premium
    FROM dbo.policy_version AS v
    WHERE v.policy_id = p.policy_id
    ORDER BY v.effective_from DESC, v.version_no DESC
) AS cv
WHERE p.status = 'ACTIVE';
GO
