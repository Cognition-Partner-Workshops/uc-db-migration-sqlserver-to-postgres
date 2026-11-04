CREATE TABLE dbo.claim_payment (
    claim_payment_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_claim_payment PRIMARY KEY,
    claim_id INT NOT NULL CONSTRAINT fk_claim_payment_claim REFERENCES dbo.claim (claim_id),
    reserve_type VARCHAR(10) NOT NULL,
    paid_at DATETIME2(3) NOT NULL,
    amount DECIMAL(19, 4) NOT NULL,
    payee_name NVARCHAR(200) NOT NULL,
    payee_iban VARCHAR(34) NULL
);
GO
CREATE INDEX ix_claim_payment_claim ON dbo.claim_payment (claim_id, reserve_type);
GO
