-- Pay against a claim reserve; never pay more than is reserved.
CREATE OR ALTER PROCEDURE dbo.usp_claim_payment_record
    @claim_id INT,
    @reserve_type VARCHAR(10),
    @amount DECIMAL(19, 4),
    @payee_name NVARCHAR(200),
    @payee_iban VARCHAR(34) = NULL,
    @paid_at DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @status VARCHAR(10);
    DECLARE @reserve DECIMAL(19, 4);
    DECLARE @paid DECIMAL(19, 4);
    DECLARE @payment_rows INT;

    BEGIN TRY
        SELECT @status = status FROM dbo.claim WHERE claim_id = @claim_id;

        IF @status IS NULL OR @status NOT IN ('OPEN', 'REOPENED')
            RAISERROR (N'Claim %d is not open for payment', 16, 1, @claim_id);

        SELECT @reserve = amount
        FROM dbo.claim_reserve
        WHERE claim_id = @claim_id AND reserve_type = @reserve_type;

        SELECT @paid = ISNULL(SUM(amount), 0)
        FROM dbo.claim_payment
        WHERE claim_id = @claim_id AND reserve_type = @reserve_type;

        IF @paid + @amount > ISNULL(@reserve, 0)
            RAISERROR (N'Payment exceeds the outstanding %s reserve', 16, 1, @reserve_type);

        BEGIN TRANSACTION;

        INSERT INTO dbo.claim_payment (claim_id, reserve_type, paid_at, amount, payee_name, payee_iban)
        VALUES (@claim_id, UPPER(@reserve_type), @paid_at, @amount, @payee_name, @payee_iban);

        SET @payment_rows = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT
            @claim_id AS claim_id,
            UPPER(@reserve_type) AS reserve_type,
            @amount AS amount,
            @payment_rows AS rows_written,
            ISNULL(@reserve, 0) - @paid - @amount AS outstanding_after;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
