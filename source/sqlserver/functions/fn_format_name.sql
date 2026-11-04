-- Display name for letters and screens: "First Middle Last".
CREATE OR ALTER FUNCTION dbo.fn_format_name (
    @first_name NVARCHAR(100),
    @middle_name NVARCHAR(100),
    @last_name NVARCHAR(100)
)
RETURNS NVARCHAR(300)
WITH SCHEMABINDING
AS
BEGIN
    RETURN LTRIM(RTRIM(@first_name)) + N' '
        + ISNULL(NULLIF(LTRIM(RTRIM(@middle_name)), N'') + N' ', N'')
        + LTRIM(RTRIM(@last_name));
END;
GO
