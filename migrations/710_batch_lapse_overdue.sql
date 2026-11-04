-- dbo.usp_batch_lapse_overdue. The cursor becomes a FOR loop; one UPDATE per
-- policy keeps the per-statement audit rows the legacy trigger writes.
CREATE FUNCTION $(NS).usp_batch_lapse_overdue(p_run_date date)
RETURNS TABLE (policies_lapsed integer, installments_cancelled integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_policy_id integer;
    v_rows integer;
    v_lapsed integer := 0;
    v_cancelled integer := 0;
BEGIN
    FOR v_policy_id IN
        SELECT ps.policy_id
        FROM $(NS).premium_schedule AS ps
        INNER JOIN $(NS).policy AS p ON p.policy_id = ps.policy_id
        WHERE ps.status = 'OVERDUE' AND p.status = 'ACTIVE'
        GROUP BY ps.policy_id
        HAVING $(NS).fn_months_between(min(ps.due_date), p_run_date) >= 2
        ORDER BY ps.policy_id
    LOOP
        UPDATE $(NS).policy SET status = 'LAPSED', updated_at = p_run_date::timestamp WHERE policy_id = v_policy_id;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_lapsed := v_lapsed + v_rows;

        UPDATE $(NS).premium_schedule
        SET status = 'CANCELLED'
        WHERE policy_id = v_policy_id AND status = 'DUE' AND due_date >= p_run_date;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_cancelled := v_cancelled + v_rows;
    END LOOP;

    RETURN QUERY SELECT v_lapsed, v_cancelled;
END;
$$;
