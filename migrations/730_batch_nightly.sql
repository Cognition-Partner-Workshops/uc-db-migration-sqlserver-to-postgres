-- dbo.usp_batch_nightly. INSERT ... EXEC becomes direct calls; the CATCH
-- re-raises with the legacy prefix.
CREATE FUNCTION $(NS).usp_batch_nightly(p_run_date date DEFAULT NULL)
RETURNS TABLE (
    run_date date,
    marked_overdue integer,
    policies_affected integer,
    policies_lapsed integer,
    installments_cancelled integer,
    brokers_changed integer,
    brokers_deactivated integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_date date := coalesce(p_run_date, (now() AT TIME ZONE 'UTC')::date);
    o record;
    l record;
    c record;
BEGIN
    BEGIN
        SELECT * INTO o FROM $(NS).usp_batch_mark_overdue(v_run_date);
        SELECT * INTO l FROM $(NS).usp_batch_lapse_overdue(v_run_date);
        SELECT * INTO c FROM $(NS).usp_batch_sync_broker_commission(v_run_date);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Nightly batch failed: %', SQLERRM USING ERRCODE = 'P0001', HINT = 'tsql:50000';
    END;

    RETURN QUERY SELECT
        v_run_date, o.marked_overdue, o.policies_affected, l.policies_lapsed,
        l.installments_cancelled, c.brokers_changed, c.brokers_deactivated;
END;
$$;
