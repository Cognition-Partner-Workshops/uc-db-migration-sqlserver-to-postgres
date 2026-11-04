-- New-business quote: base rate, age loading, minimum premium, premium tax.
CREATE OR ALTER PROCEDURE dbo.usp_rate_quote
    @product_code VARCHAR(20),
    @country_code CHAR(2),
    @sum_insured DECIMAL(19, 4),
    @date_of_birth DATE,
    @start_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @base_rate DECIMAL(9, 6);
    DECLARE @min_premium MONEY;
    DECLARE @tax_rate DECIMAL(5, 4);
    DECLARE @age INT;
    DECLARE @loading DECIMAL(5, 4);
    DECLARE @net MONEY;
    DECLARE @tax MONEY;

    SELECT @base_rate = base_rate, @min_premium = min_premium
    FROM ref.product
    WHERE product_code = @product_code AND is_active = 1;

    IF @base_rate IS NULL
        THROW 50100, N'Unknown or inactive product', 1;

    SELECT @tax_rate = premium_tax_rate FROM ref.country WHERE country_code = @country_code;

    IF @tax_rate IS NULL
        THROW 50101, N'Unknown country code', 1;

    SET @age = DATEDIFF(YEAR, @date_of_birth, @start_date)
        - IIF(DATEADD(YEAR, DATEDIFF(YEAR, @date_of_birth, @start_date), @date_of_birth) > @start_date, 1, 0);

    SET @loading = CASE
        WHEN @age < 25 THEN 0.2500
        WHEN @age >= 70 THEN 0.1500
        ELSE 0
    END;

    SET @net = @sum_insured * @base_rate * (1 + @loading);
    SET @net = IIF(@net < @min_premium, @min_premium, @net);
    SET @tax = @net * @tax_rate;

    SELECT
        UPPER(@product_code) AS product_code,
        @age AS rated_age,
        @loading AS age_loading,
        ROUND(@net, 2) AS net_premium,
        ROUND(@tax, 2) AS premium_tax,
        ROUND(@net, 2) + ROUND(@tax, 2) AS gross_premium;
END;
GO
