-- Renewal terms: no-claims discount by tenure, loading by recent claims.
CREATE OR ALTER PROCEDURE dbo.usp_rate_renewal
    @policy_id INT,
    @renewal_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tenure_months INT;
    DECLARE @premium MONEY;
    DECLARE @sum_insured DECIMAL(19, 4);
    DECLARE @claims INT;
    DECLARE @discount DECIMAL(5, 4);
    DECLARE @loading DECIMAL(5, 4);

    SELECT @tenure_months = DATEDIFF(MONTH, inception_date, @renewal_date)
    FROM dbo.policy
    WHERE policy_id = @policy_id;

    IF @tenure_months IS NULL
        THROW 50120, N'Policy not found', 1;

    -- current terms
    SELECT TOP (1)
        @premium = annual_premium,
        @sum_insured = sum_insured
    FROM dbo.policy_version
    WHERE policy_id = @policy_id;

    SELECT @claims = COUNT(*)
    FROM dbo.claim
    WHERE policy_id = @policy_id
        AND loss_date >= DATEADD(MONTH, -36, @renewal_date)
        AND status <> 'DENIED';

    SET @discount = CASE
        WHEN @claims > 0 THEN 0
        WHEN @tenure_months >= 60 THEN 0.1500
        WHEN @tenure_months >= 36 THEN 0.1000
        WHEN @tenure_months >= 12 THEN 0.0500
        ELSE 0
    END;

    SET @loading = CASE
        WHEN @claims >= 3 THEN 0.5000
        WHEN @claims = 2 THEN 0.2500
        WHEN @claims = 1 THEN 0.1000
        ELSE 0
    END;

    SELECT
        @policy_id AS policy_id,
        @tenure_months AS tenure_months,
        @claims AS claims_36m,
        @sum_insured AS sum_insured,
        @premium AS current_premium,
        @discount AS ncd_discount,
        @loading AS claims_loading,
        ROUND(@premium * (1 - @discount + @loading), 2) AS renewal_premium;
END;
GO
