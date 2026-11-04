CREATE TABLE dbo.policyholder (
    policyholder_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_policyholder PRIMARY KEY,
    external_ref UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT df_policyholder_ref DEFAULT (NEWID())
        CONSTRAINT uq_policyholder_ref UNIQUE,
    first_name NVARCHAR(100) NOT NULL,
    middle_name NVARCHAR(100) NULL,
    last_name NVARCHAR(100) NOT NULL,
    -- computed column used by search screens and correspondence
    full_name AS (first_name + N' ' + last_name) PERSISTED,
    date_of_birth DATE NOT NULL,
    email NVARCHAR(200) NULL,
    phone VARCHAR(30) NULL,
    iban VARCHAR(34) NOT NULL,
    address_line NVARCHAR(200) NOT NULL,
    postcode VARCHAR(12) NOT NULL,
    city NVARCHAR(100) NOT NULL,
    country_code CHAR(2) NOT NULL CONSTRAINT fk_policyholder_country REFERENCES ref.country (country_code),
    created_at DATETIMEOFFSET(3) NOT NULL CONSTRAINT df_policyholder_created DEFAULT (SYSDATETIMEOFFSET()),
    row_ver ROWVERSION
);
GO
CREATE INDEX ix_policyholder_last_name ON dbo.policyholder (last_name, first_name);
GO
CREATE INDEX ix_policyholder_email ON dbo.policyholder (email) WHERE email IS NOT NULL;
GO
