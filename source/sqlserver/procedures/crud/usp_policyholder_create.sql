-- Create a policyholder and return the new row.
CREATE OR ALTER PROCEDURE dbo.usp_policyholder_create
    @first_name NVARCHAR(100),
    @middle_name NVARCHAR(100) = NULL,
    @last_name NVARCHAR(100),
    @date_of_birth DATE,
    @email NVARCHAR(200) = NULL,
    @phone VARCHAR(30) = NULL,
    @iban VARCHAR(34),
    @address_line NVARCHAR(200),
    @postcode VARCHAR(12),
    @city NVARCHAR(100),
    @country_code CHAR(2),
    @policyholder_id INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM ref.country WHERE country_code = @country_code)
        THROW 50001, N'Unknown country code', 1;

    IF @email IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.policyholder WHERE email = @email)
        THROW 50002, N'A policyholder with this email already exists', 1;

    INSERT INTO dbo.policyholder (
        first_name, middle_name, last_name, date_of_birth, email, phone,
        iban, address_line, postcode, city, country_code
    )
    VALUES (
        @first_name, @middle_name, @last_name, @date_of_birth, @email, @phone,
        REPLACE(UPPER(@iban), ' ', ''), @address_line, @postcode, @city, UPPER(@country_code)
    );

    SET @policyholder_id = SCOPE_IDENTITY();

    SELECT
        policyholder_id,
        first_name,
        middle_name,
        last_name,
        full_name,
        date_of_birth,
        email,
        iban,
        city,
        country_code
    FROM dbo.policyholder
    WHERE policyholder_id = @policyholder_id;
END;
GO
