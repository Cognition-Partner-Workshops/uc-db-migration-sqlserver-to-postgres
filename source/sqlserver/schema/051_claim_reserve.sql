-- Current reserve per claim and reserve type (maintained by MERGE).
CREATE TABLE dbo.claim_reserve (
    reserve_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_claim_reserve PRIMARY KEY,
    claim_id INT NOT NULL CONSTRAINT fk_reserve_claim REFERENCES dbo.claim (claim_id),
    reserve_type VARCHAR(10) NOT NULL CONSTRAINT ck_reserve_type CHECK (reserve_type IN ('INDEMNITY', 'EXPENSE')),
    amount DECIMAL(19, 4) NOT NULL,
    set_at DATETIME2(3) NOT NULL,
    set_by NVARCHAR(50) NOT NULL,
    CONSTRAINT uq_claim_reserve UNIQUE (claim_id, reserve_type)
);
GO
