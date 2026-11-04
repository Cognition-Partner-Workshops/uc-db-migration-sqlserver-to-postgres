-- Mid-term change: close the open version and add a new one.
CREATE OR ALTER PROCEDURE dbo.usp_policy_endorse
    @policy_id INT,
    @effective_from DATE,
    @sum_insured DECIMAL(19, 4),
    @annual_premium MONEY,
    @change_reason NVARCHAR(200),
    @as_of DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(3) = ISNULL(@as_of, SYSUTCDATETIME());
    DECLARE @status VARCHAR(10);
    DECLARE @policy_number VARCHAR(20);
    DECLARE @next_version INT;

    SELECT @status = status, @policy_number = policy_number
    FROM dbo.policy
    WHERE policy_id = @policy_id;

    IF @status IS NULL
        THROW 50020, N'Policy not found', 1;

    IF @status <> 'ACTIVE'
    BEGIN
        RAISERROR (N'Policy %s is not active', 16, 1, @policy_number);
        RETURN;
    END;

    SELECT @next_version = MAX(version_no) + 1
    FROM dbo.policy_version
    WHERE policy_id = @policy_id;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.policy_version
        SET effective_to = DATEADD(DAY, -1, @effective_from)
        WHERE policy_id = @policy_id AND effective_to IS NULL;

        INSERT INTO dbo.policy_version (
            policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium,
            change_reason, created_at
        )
        OUTPUT
            inserted.policy_id,
            inserted.version_no,
            inserted.effective_from,
            inserted.sum_insured,
            inserted.annual_premium,
            inserted.change_reason
        VALUES (
            @policy_id, @next_version, @effective_from, NULL, @sum_insured, @annual_premium,
            @change_reason, @now
        );

        UPDATE dbo.policy
        SET annual_premium = @annual_premium, updated_at = @now
        WHERE policy_id = @policy_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
