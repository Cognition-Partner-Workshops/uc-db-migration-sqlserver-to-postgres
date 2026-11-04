CREATE TABLE ref.country (
    country_code CHAR(2) NOT NULL CONSTRAINT pk_country PRIMARY KEY,
    country_name NVARCHAR(100) NOT NULL,
    currency_code CHAR(3) NOT NULL,
    is_eu_member BIT NOT NULL CONSTRAINT df_country_eu DEFAULT (1),
    premium_tax_rate DECIMAL(5, 4) NOT NULL
);
GO
