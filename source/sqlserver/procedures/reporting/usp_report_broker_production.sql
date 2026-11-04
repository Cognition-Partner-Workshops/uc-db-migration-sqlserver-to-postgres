-- Top brokers by live premium, with optional filters (dynamic SQL).
CREATE OR ALTER PROCEDURE dbo.usp_report_broker_production
    @country_code CHAR(2) = NULL,
    @line_of_business VARCHAR(20) = NULL,
    @top_n INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) = N'
SELECT TOP (@top_n) WITH TIES
    b.broker_code,
    b.broker_name + N'' <'' + b.email + N''>'' AS broker_contact,
    b.country_code,
    COUNT(*) AS live_policies,
    COUNT(DISTINCT pr.product_code) AS products,
    SUM(p.annual_premium) AS gross_written_premium
FROM dbo.policy AS p
INNER JOIN dbo.broker AS b ON b.broker_id = p.broker_id
INNER JOIN ref.product AS pr ON pr.product_id = p.product_id
WHERE p.status = ''ACTIVE''';

    IF @country_code IS NOT NULL
        SET @sql += N'
    AND b.country_code = @country_code';

    IF @line_of_business IS NOT NULL
        SET @sql += N'
    AND pr.line_of_business = @line_of_business';

    SET @sql += N'
GROUP BY b.broker_code, b.broker_name, b.email, b.country_code
ORDER BY SUM(p.annual_premium) DESC;';

    EXEC sys.sp_executesql
        @sql,
        N'@top_n INT, @country_code CHAR(2), @line_of_business VARCHAR(20)',
        @top_n = @top_n,
        @country_code = @country_code,
        @line_of_business = @line_of_business;
END;
GO
