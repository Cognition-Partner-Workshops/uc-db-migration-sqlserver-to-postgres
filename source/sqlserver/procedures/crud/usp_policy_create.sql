-- Bind a new policy: policy row (number from the sequence default) plus version 1.
CREATE OR ALTER PROCEDURE dbo.usp_policy_create
    @policyholder_id INT,
    @product_code VARCHAR(20),
    @broker_code VARCHAR(20) = NULL,
    @inception_date DATE,
    @payment_frequency TINYINT = 1,
    @sum_insured DECIMAL(19, 4),
    @annual_premium MONEY,
    @as_of DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(3) = ISNULL(@as_of, SYSUTCDATETIME());
    DECLARE @product_id INT;
    DECLARE @broker_id INT;
    DECLARE @new TABLE (policy_id INT NOT NULL, policy_number VARCHAR(20) NOT NULL);

    SELECT @product_id = product_id
    FROM ref.product
    WHERE product_code = @product_code AND is_active = 1;

    IF @product_id IS NULL
        THROW 50010, N'Unknown or inactive product', 1;

    IF @broker_code IS NOT NULL
    BEGIN
        SELECT @broker_id = broker_id FROM dbo.broker WHERE broker_code = @broker_code;
        IF @broker_id IS NULL
            THROW 50011, N'Unknown broker', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.policy (
            policyholder_id, broker_id, product_id, status, inception_date, expiry_date,
            payment_frequency, annual_premium, created_at
        )
        OUTPUT inserted.policy_id, inserted.policy_number INTO @new (policy_id, policy_number)
        VALUES (
            @policyholder_id, @broker_id, @product_id, 'ACTIVE', @inception_date,
            DATEADD(DAY, -1, DATEADD(YEAR, 1, @inception_date)),
            @payment_frequency, @annual_premium, @now
        );

        INSERT INTO dbo.policy_version (
            policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium,
            change_reason, created_at
        )
        SELECT policy_id, 1, @inception_date, NULL, @sum_insured, @annual_premium, N'New business', @now
        FROM @new;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT
        p.policy_id,
        p.policy_number,
        p.policyholder_id,
        p.broker_id,
        p.product_id,
        p.status,
        p.inception_date,
        p.expiry_date,
        p.payment_frequency,
        p.annual_premium
    FROM dbo.policy AS p
    INNER JOIN @new AS n ON n.policy_id = p.policy_id;
END;
GO
