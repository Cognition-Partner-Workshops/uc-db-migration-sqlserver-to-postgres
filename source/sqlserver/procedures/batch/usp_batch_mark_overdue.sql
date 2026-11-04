-- Flag installments more than 14 days past due.
CREATE OR ALTER PROCEDURE dbo.usp_batch_mark_overdue
    @run_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @changed TABLE (schedule_id INT NOT NULL PRIMARY KEY, policy_id INT NOT NULL);

    UPDATE dbo.premium_schedule
    SET status = 'OVERDUE'
    OUTPUT inserted.schedule_id, inserted.policy_id INTO @changed (schedule_id, policy_id)
    WHERE status = 'DUE'
        AND due_date < DATEADD(DAY, -14, @run_date)
        AND paid_amount < amount_due;

    SELECT
        COUNT(*) AS marked_overdue,
        COUNT(DISTINCT policy_id) AS policies_affected
    FROM @changed;
END;
GO
