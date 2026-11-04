-- Audit policy status changes. row_count records how many rows the
-- triggering statement touched.
CREATE OR ALTER TRIGGER dbo.trg_policy_status_audit
ON dbo.policy
AFTER UPDATE
AS
BEGIN
    DECLARE @rows INT = @@ROWCOUNT;
    IF @rows = 0
        RETURN;
    SET NOCOUNT ON;

    IF UPDATE(status)
        INSERT INTO dbo.audit_log (table_name, action, key_value, old_value, new_value, row_count)
        SELECT N'policy', 'STATUS', i.policy_number, d.status, i.status, @rows
        FROM inserted AS i
        INNER JOIN deleted AS d ON d.policy_id = i.policy_id
        WHERE i.status <> d.status;
END;
GO
