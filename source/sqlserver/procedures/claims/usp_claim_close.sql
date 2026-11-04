-- Close a claim (optimistic concurrency on ROWVERSION) and release unpaid reserve.
CREATE OR ALTER PROCEDURE dbo.usp_claim_close
    @claim_id INT,
    @expected_row_ver BINARY(8) = NULL,
    @as_of DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = ISNULL(@as_of, SYSUTCDATETIME());

    BEGIN TRANSACTION;

    UPDATE dbo.claim
    SET status = 'CLOSED', closed_at = @now
    WHERE claim_id = @claim_id
        AND status IN ('OPEN', 'REOPENED')
        AND (@expected_row_ver IS NULL OR row_ver = @expected_row_ver);

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50230, N'Claim is not open or was changed by another user', 1;
    END;

    UPDATE r
    SET amount = ISNULL(p.paid, 0),
        set_at = CAST(@now AS DATETIME2(3)),
        set_by = N'claims.close'
    FROM dbo.claim_reserve AS r
    OUTER APPLY (
        SELECT SUM(cp.amount) AS paid
        FROM dbo.claim_payment AS cp
        WHERE cp.claim_id = r.claim_id AND cp.reserve_type = r.reserve_type
    ) AS p
    WHERE r.claim_id = @claim_id;

    COMMIT TRANSACTION;

    SELECT claim_id, claim_number, status, closed_at
    FROM dbo.claim
    WHERE claim_id = @claim_id;
END;
GO
