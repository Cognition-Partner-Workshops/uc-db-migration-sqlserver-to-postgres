CREATE TABLE dbo.policy (
    policy_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_policy PRIMARY KEY,
    policy_number VARCHAR(20) NOT NULL
        CONSTRAINT df_policy_number
        DEFAULT ('P' + RIGHT('000000000' + CAST(NEXT VALUE FOR dbo.seq_policy_number AS VARCHAR(10)), 9))
        CONSTRAINT uq_policy_number UNIQUE,
    policyholder_id INT NOT NULL CONSTRAINT fk_policy_holder REFERENCES dbo.policyholder (policyholder_id),
    broker_id INT NULL CONSTRAINT fk_policy_broker REFERENCES dbo.broker (broker_id),
    product_id INT NOT NULL CONSTRAINT fk_policy_product REFERENCES ref.product (product_id),
    status VARCHAR(10) NOT NULL
        CONSTRAINT ck_policy_status CHECK (status IN ('QUOTE', 'ACTIVE', 'LAPSED', 'CANCELLED', 'EXPIRED')),
    inception_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    payment_frequency TINYINT NOT NULL
        CONSTRAINT ck_policy_frequency CHECK (payment_frequency IN (1, 2, 4, 12)),
    annual_premium MONEY NOT NULL,
    currency_code CHAR(3) NOT NULL CONSTRAINT df_policy_currency DEFAULT ('EUR'),
    created_at DATETIME2(3) NOT NULL CONSTRAINT df_policy_created DEFAULT (SYSUTCDATETIME()),
    updated_at DATETIME2(3) NULL,
    row_ver ROWVERSION
);
GO
CREATE INDEX ix_policy_holder ON dbo.policy (policyholder_id);
GO
CREATE INDEX ix_policy_broker ON dbo.policy (broker_id) INCLUDE (annual_premium, status);
GO
