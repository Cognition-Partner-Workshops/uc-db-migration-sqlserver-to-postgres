-- Record an incoming premium payment and allocate it to an installment.
CREATE OR ALTER PROCEDURE dbo.usp_premium_payment_record
    @policy_id INT,
    @schedule_id INT = NULL,
    @amount MONEY,
    @method VARCHAR(10),
    @paid_at DATETIMEOFFSET(3),
    @payer_iban VARCHAR(34) = NULL,
    @reference_text NVARCHAR(140) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @amount <= 0
        THROW 50030, N'Payment amount must be positive', 1;

    IF @schedule_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM dbo.premium_schedule
            WHERE schedule_id = @schedule_id AND policy_id = @policy_id
        )
        THROW 50031, N'Installment does not belong to policy', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.premium_payment (
        policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text
    )
    OUTPUT
        inserted.policy_id,
        inserted.schedule_id,
        inserted.paid_at,
        inserted.amount,
        inserted.method,
        inserted.reference_text
    VALUES (
        @policy_id, @schedule_id, @paid_at, @amount, UPPER(@method),
        NULLIF(REPLACE(@payer_iban, ' ', ''), ''), ISNULL(@reference_text, N'')
    );

    IF @schedule_id IS NOT NULL
        UPDATE dbo.premium_schedule
        SET paid_amount = paid_amount + @amount,
            status = IIF(paid_amount + @amount >= amount_due, 'PAID', status)
        WHERE schedule_id = @schedule_id;

    COMMIT TRANSACTION;
END;
GO
