-- One row per policy version. The clustered index keeps each policy's
-- versions newest-first so the "current version" is the first row read.
CREATE TABLE dbo.policy_version (
    policy_version_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_policy_version PRIMARY KEY NONCLUSTERED,
    policy_id INT NOT NULL CONSTRAINT fk_version_policy REFERENCES dbo.policy (policy_id),
    version_no INT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    sum_insured DECIMAL(19, 4) NOT NULL,
    annual_premium MONEY NOT NULL,
    change_reason NVARCHAR(200) NULL,
    created_at DATETIME2(3) NOT NULL CONSTRAINT df_version_created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT uq_policy_version UNIQUE (policy_id, version_no)
);
GO
CREATE CLUSTERED INDEX cx_policy_version_latest
ON dbo.policy_version (policy_id, effective_from DESC, version_no DESC);
GO
