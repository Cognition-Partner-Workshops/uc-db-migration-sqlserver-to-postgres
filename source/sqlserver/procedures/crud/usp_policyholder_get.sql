-- Look a policyholder up by id or by email address.
CREATE OR ALTER PROCEDURE dbo.usp_policyholder_get
    @policyholder_id INT = NULL,
    @email NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ph.policyholder_id,
        ph.external_ref,
        dbo.fn_format_name(ph.first_name, ph.middle_name, ph.last_name) AS display_name,
        ph.date_of_birth,
        ph.email,
        ph.iban,
        ph.postcode,
        ph.city,
        c.country_name,
        COALESCE(pc.policy_count, 0) AS policy_count
    FROM dbo.policyholder AS ph
    INNER JOIN ref.country AS c ON c.country_code = ph.country_code
    OUTER APPLY (
        SELECT COUNT(*) AS policy_count
        FROM dbo.policy AS p
        WHERE p.policyholder_id = ph.policyholder_id
    ) AS pc
    WHERE (@policyholder_id IS NULL OR ph.policyholder_id = @policyholder_id)
        AND (@email IS NULL OR ph.email = @email)
        AND (@policyholder_id IS NOT NULL OR @email IS NOT NULL);
END;
GO
