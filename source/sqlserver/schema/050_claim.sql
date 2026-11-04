CREATE TABLE dbo.claim (
    claim_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_claim PRIMARY KEY,
    claim_number VARCHAR(20) NOT NULL CONSTRAINT uq_claim_number UNIQUE,
    policy_id INT NOT NULL CONSTRAINT fk_claim_policy REFERENCES dbo.policy (policy_id),
    loss_date DATE NOT NULL,
    reported_at DATETIME2(0) NOT NULL,
    cause_code VARCHAR(10) NULL,
    status VARCHAR(10) NOT NULL
        CONSTRAINT ck_claim_status CHECK (status IN ('OPEN', 'CLOSED', 'REOPENED', 'DENIED')),
    description NVARCHAR(400) NULL,
    closed_at DATETIME2(0) NULL,
    row_ver ROWVERSION
);
GO
CREATE INDEX ix_claim_policy ON dbo.claim (policy_id, loss_date);
GO
