-- Whole calendar months between two dates, as the business counts them:
-- every month boundary crossed counts as one month.
CREATE OR ALTER FUNCTION dbo.fn_months_between (@from_date DATE, @to_date DATE)
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN DATEDIFF(MONTH, @from_date, @to_date);
END;
GO
