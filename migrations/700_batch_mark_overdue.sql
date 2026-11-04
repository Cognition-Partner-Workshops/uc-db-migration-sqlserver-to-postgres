-- dbo.usp_batch_mark_overdue. UPDATE ... OUTPUT INTO @table becomes a data-modifying CTE.
CREATE FUNCTION $(NS).usp_batch_mark_overdue(p_run_date date)
RETURNS TABLE (marked_overdue integer, policies_affected integer)
LANGUAGE sql
AS $$
    WITH changed AS (
        UPDATE $(NS).premium_schedule AS s
        SET status = 'OVERDUE'
        WHERE s.status = 'DUE'
            AND s.due_date < p_run_date - 14
            AND s.paid_amount < s.amount_due
        RETURNING s.schedule_id, s.policy_id
    )
    SELECT count(*)::integer, count(DISTINCT policy_id)::integer FROM changed
$$;
