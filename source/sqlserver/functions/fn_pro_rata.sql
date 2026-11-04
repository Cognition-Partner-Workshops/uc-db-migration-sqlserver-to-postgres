-- Pro-rata share of an amount for @days out of @period_days.
-- Kept in MONEY end to end: finance signed off on these figures.
CREATE OR ALTER FUNCTION dbo.fn_pro_rata (@amount MONEY, @days INT, @period_days INT)
RETURNS MONEY
WITH SCHEMABINDING
AS
BEGIN
    IF @period_days IS NULL OR @period_days = 0
        RETURN NULL;
    RETURN @amount * @days / @period_days;
END;
GO
