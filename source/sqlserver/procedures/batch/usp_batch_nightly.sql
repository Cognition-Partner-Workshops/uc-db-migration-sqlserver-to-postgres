-- Nightly batch. SQL Server Express has no SQL Server Agent, so this is
-- invoked by an external scheduler (here: `make batch`).
CREATE OR ALTER PROCEDURE dbo.usp_batch_nightly
    @run_date DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg NVARCHAR(2048);
    SET @run_date = ISNULL(@run_date, CAST(SYSUTCDATETIME() AS DATE));

    CREATE TABLE #overdue (marked_overdue INT, policies_affected INT);
    CREATE TABLE #lapse (policies_lapsed INT, installments_cancelled INT);
    CREATE TABLE #commission (brokers_changed INT, brokers_deactivated INT);

    BEGIN TRY
        INSERT INTO #overdue EXEC dbo.usp_batch_mark_overdue @run_date = @run_date;
        INSERT INTO #lapse EXEC dbo.usp_batch_lapse_overdue @run_date = @run_date;
        INSERT INTO #commission EXEC dbo.usp_batch_sync_broker_commission @run_date = @run_date;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        RAISERROR (N'Nightly batch failed: %s', 16, 1, @msg);
        RETURN;
    END CATCH;

    SELECT
        @run_date AS run_date,
        o.marked_overdue,
        o.policies_affected,
        l.policies_lapsed,
        l.installments_cancelled,
        c.brokers_changed,
        c.brokers_deactivated
    FROM #overdue AS o
    CROSS JOIN #lapse AS l
    CROSS JOIN #commission AS c;
END;
GO
