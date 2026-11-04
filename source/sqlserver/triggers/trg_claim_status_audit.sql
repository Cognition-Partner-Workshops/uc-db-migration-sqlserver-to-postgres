-- Audit claim status changes (open/close/reopen/deny).
CREATE OR ALTER TRIGGER dbo.trg_claim_status_audit
ON dbo.claim
AFTER UPDATE
AS
BEGIN
    DECLARE @rows INT = @@ROWCOUNT;
    IF @rows = 0
        RETURN;
    SET NOCOUNT ON;

    IF UPDATE(status)
        INSERT INTO dbo.audit_log (table_name, action, key_value, old_value, new_value, row_count)
        SELECT N'claim', 'STATUS', i.claim_number, d.status, i.status, @rows
        FROM inserted AS i
        INNER JOIN deleted AS d ON d.claim_id = i.claim_id
        WHERE i.status <> d.status;
END;
GO
