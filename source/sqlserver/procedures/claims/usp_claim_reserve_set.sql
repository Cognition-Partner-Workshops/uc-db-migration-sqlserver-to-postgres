-- Set (insert or update) the current reserve for a claim and reserve type.
CREATE OR ALTER PROCEDURE dbo.usp_claim_reserve_set
    @claim_id INT,
    @reserve_type VARCHAR(10),
    @amount DECIMAL(19, 4),
    @set_by NVARCHAR(50),
    @as_of DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2(3) = ISNULL(@as_of, SYSUTCDATETIME());
    DECLARE @paid DECIMAL(19, 4);
    DECLARE @result TABLE (
        merge_action NVARCHAR(10) NOT NULL,
        reserve_type VARCHAR(10) NOT NULL,
        old_amount DECIMAL(19, 4) NULL,
        new_amount DECIMAL(19, 4) NOT NULL
    );

    IF NOT EXISTS (SELECT 1 FROM dbo.claim WHERE claim_id = @claim_id AND status IN ('OPEN', 'REOPENED'))
        THROW 50210, N'Claim is not open', 1;

    SELECT @paid = ISNULL(SUM(amount), 0)
    FROM dbo.claim_payment
    WHERE claim_id = @claim_id AND reserve_type = @reserve_type;

    IF @amount < @paid
        THROW 50211, N'Reserve cannot be lower than the amount already paid', 1;

    MERGE dbo.claim_reserve AS t
    USING (
        SELECT
            @claim_id AS claim_id,
            UPPER(@reserve_type) AS reserve_type,
            @amount AS amount
    ) AS s
        ON t.claim_id = s.claim_id AND t.reserve_type = s.reserve_type
    WHEN MATCHED THEN
        UPDATE SET amount = s.amount, set_at = @now, set_by = @set_by
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (claim_id, reserve_type, amount, set_at, set_by)
        VALUES (s.claim_id, s.reserve_type, s.amount, @now, @set_by)
    OUTPUT $action, inserted.reserve_type, deleted.amount, inserted.amount
    INTO @result (merge_action, reserve_type, old_amount, new_amount);

    SELECT merge_action, reserve_type, old_amount, new_amount FROM @result;
END;
GO
