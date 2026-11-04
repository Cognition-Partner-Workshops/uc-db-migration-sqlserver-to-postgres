CREATE TABLE dbo.premium_payment (
    payment_id BIGINT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_premium_payment PRIMARY KEY,
    payment_ref UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT df_payment_ref DEFAULT (NEWID())
        CONSTRAINT uq_payment_ref UNIQUE,
    policy_id INT NOT NULL CONSTRAINT fk_payment_policy REFERENCES dbo.policy (policy_id),
    schedule_id INT NULL CONSTRAINT fk_payment_schedule REFERENCES dbo.premium_schedule (schedule_id),
    paid_at DATETIMEOFFSET(3) NOT NULL,
    amount MONEY NOT NULL,
    method VARCHAR(10) NOT NULL CONSTRAINT ck_payment_method CHECK (method IN ('SEPA_DD', 'CARD', 'TRANSFER')),
    payer_iban VARCHAR(34) NULL,
    reference_text NVARCHAR(140) NULL
);
GO
CREATE INDEX ix_premium_payment_policy ON dbo.premium_payment (policy_id, paid_at);
GO
