CREATE TABLE ref.product (
    product_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_product PRIMARY KEY,
    product_code VARCHAR(20) NOT NULL CONSTRAINT uq_product_code UNIQUE,
    product_name NVARCHAR(100) NOT NULL,
    line_of_business VARCHAR(20) NOT NULL,
    base_rate DECIMAL(9, 6) NOT NULL,
    min_premium MONEY NOT NULL,
    is_active BIT NOT NULL CONSTRAINT df_product_active DEFAULT (1)
);
GO
