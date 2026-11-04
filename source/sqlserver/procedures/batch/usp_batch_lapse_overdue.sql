-- Lapse active policies whose oldest overdue installment is two months old.
CREATE OR ALTER PROCEDURE dbo.usp_batch_lapse_overdue
    @run_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @policy_id INT;
    DECLARE @lapsed INT = 0;
    DECLARE @cancelled INT = 0;

    DECLARE lapse_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ps.policy_id
    FROM dbo.premium_schedule AS ps
    INNER JOIN dbo.policy AS p ON p.policy_id = ps.policy_id
    WHERE ps.status = 'OVERDUE' AND p.status = 'ACTIVE'
    GROUP BY ps.policy_id
    HAVING DATEDIFF(MONTH, MIN(ps.due_date), @run_date) >= 2
    ORDER BY ps.policy_id;

    OPEN lapse_cursor;
    FETCH NEXT FROM lapse_cursor INTO @policy_id;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE dbo.policy
        SET status = 'LAPSED', updated_at = CAST(@run_date AS DATETIME2(3))
        WHERE policy_id = @policy_id;
        SET @lapsed += @@ROWCOUNT;

        UPDATE dbo.premium_schedule
        SET status = 'CANCELLED'
        WHERE policy_id = @policy_id AND status = 'DUE' AND due_date >= @run_date;
        SET @cancelled += @@ROWCOUNT;

        FETCH NEXT FROM lapse_cursor INTO @policy_id;
    END;

    CLOSE lapse_cursor;
    DEALLOCATE lapse_cursor;

    SELECT @lapsed AS policies_lapsed, @cancelled AS installments_cancelled;
END;
GO
