CREATE TABLE dbo.coverage (
    coverage_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_coverage PRIMARY KEY,
    policy_id INT NOT NULL CONSTRAINT fk_coverage_policy REFERENCES dbo.policy (policy_id),
    coverage_code VARCHAR(20) NOT NULL,
    limit_amount DECIMAL(19, 4) NOT NULL,
    deductible MONEY NOT NULL CONSTRAINT df_coverage_deductible DEFAULT (0),
    premium_share DECIMAL(7, 4) NOT NULL
);
GO
CREATE INDEX ix_coverage_policy ON dbo.coverage (policy_id, coverage_code);
GO
