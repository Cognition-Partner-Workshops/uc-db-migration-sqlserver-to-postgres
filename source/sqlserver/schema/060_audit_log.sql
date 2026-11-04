CREATE TABLE dbo.audit_log (
    audit_id BIGINT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_audit_log PRIMARY KEY,
    table_name NVARCHAR(128) NOT NULL,
    action VARCHAR(10) NOT NULL,
    key_value NVARCHAR(400) NOT NULL,
    old_value NVARCHAR(100) NULL,
    new_value NVARCHAR(100) NULL,
    row_count INT NOT NULL CONSTRAINT df_audit_rows DEFAULT (1),
    changed_at DATETIME2(3) NOT NULL CONSTRAINT df_audit_changed DEFAULT (SYSUTCDATETIME()),
    changed_by NVARCHAR(128) NOT NULL CONSTRAINT df_audit_user DEFAULT (SUSER_SNAME())
);
GO
