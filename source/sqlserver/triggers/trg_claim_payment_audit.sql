-- One audit row per payment statement: claims touched and total paid.
CREATE OR ALTER TRIGGER dbo.trg_claim_payment_audit
ON dbo.claim_payment
AFTER INSERT
AS
BEGIN
    DECLARE @rows INT = @@ROWCOUNT;
    IF @rows = 0
        RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.audit_log (table_name, action, key_value, old_value, new_value, row_count)
    SELECT
        N'claim_payment',
        'PAYMENT',
        STRING_AGG(CAST(c.claim_number AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY c.claim_number),
        NULL,
        CAST(SUM(i.amount) AS NVARCHAR(100)),
        @rows
    FROM inserted AS i
    INNER JOIN dbo.claim AS c ON c.claim_id = i.claim_id;
END;
GO
