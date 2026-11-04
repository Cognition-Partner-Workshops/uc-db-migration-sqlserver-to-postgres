CREATE TABLE dbo.broker (
    broker_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_broker PRIMARY KEY,
    broker_code VARCHAR(20) NOT NULL CONSTRAINT uq_broker_code UNIQUE,
    broker_name NVARCHAR(200) NOT NULL,
    country_code CHAR(2) NOT NULL CONSTRAINT fk_broker_country REFERENCES ref.country (country_code),
    commission_pct DECIMAL(5, 2) NOT NULL,
    email NVARCHAR(200) NULL,
    is_active BIT NOT NULL CONSTRAINT df_broker_active DEFAULT (1),
    created_at DATETIME2(3) NOT NULL CONSTRAINT df_broker_created DEFAULT (SYSUTCDATETIME())
);
GO
