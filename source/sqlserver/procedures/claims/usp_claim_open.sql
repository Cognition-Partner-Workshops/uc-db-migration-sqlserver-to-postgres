-- First notification of loss: create the claim and its initial indemnity reserve.
CREATE OR ALTER PROCEDURE dbo.usp_claim_open
    @policy_number VARCHAR(20),
    @loss_date DATE,
    @reported_at DATETIME2(0),
    @cause_code VARCHAR(10) = NULL,
    @description NVARCHAR(400) = NULL,
    @initial_estimate DECIMAL(19, 4),
    @set_by NVARCHAR(50) = N'claims.intake',
    @claim_id INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @policy_id INT;
    DECLARE @status VARCHAR(10);
    DECLARE @inception DATE;
    DECLARE @expiry DATE;
    DECLARE @sum_insured DECIMAL(19, 4);
    DECLARE @reserve DECIMAL(19, 4);
    DECLARE @claim_number VARCHAR(20);

    SELECT
        @policy_id = policy_id,
        @status = status,
        @inception = inception_date,
        @expiry = expiry_date
    FROM dbo.policy
    WHERE policy_number = @policy_number;

    IF @policy_id IS NULL
        THROW 50200, N'Policy not found', 1;

    IF @status IN ('QUOTE', 'CANCELLED')
        THROW 50201, N'Policy is not on cover', 1;

    IF @loss_date < @inception OR @loss_date > @expiry
        THROW 50202, N'Loss date is outside the period of cover', 1;

    -- sum insured of the current version
    SELECT TOP (1) @sum_insured = sum_insured
    FROM dbo.policy_version
    WHERE policy_id = @policy_id;

    SET @reserve = IIF(@initial_estimate > @sum_insured, @sum_insured, @initial_estimate);
    SET @claim_number = 'C' + RIGHT('000000000' + CAST(NEXT VALUE FOR dbo.seq_claim_number AS VARCHAR(10)), 9);

    BEGIN TRANSACTION;

    INSERT INTO dbo.claim (claim_number, policy_id, loss_date, reported_at, cause_code, status, description)
    VALUES (@claim_number, @policy_id, @loss_date, @reported_at, @cause_code, 'OPEN', @description);

    SET @claim_id = SCOPE_IDENTITY();

    INSERT INTO dbo.claim_reserve (claim_id, reserve_type, amount, set_at, set_by)
    VALUES (@claim_id, 'INDEMNITY', @reserve, CAST(@reported_at AS DATETIME2(3)), @set_by);

    COMMIT TRANSACTION;

    SELECT
        c.claim_id,
        c.claim_number,
        c.policy_id,
        c.loss_date,
        c.status,
        @sum_insured AS sum_insured,
        r.amount AS indemnity_reserve
    FROM dbo.claim AS c
    INNER JOIN dbo.claim_reserve AS r ON r.claim_id = c.claim_id AND r.reserve_type = 'INDEMNITY'
    WHERE c.claim_id = @claim_id;
END;
GO
