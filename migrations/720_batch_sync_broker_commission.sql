-- dbo.usp_batch_sync_broker_commission. MERGE ... WHEN NOT MATCHED BY SOURCE
-- needs PG17, so it becomes two UPDATEs over the same tier set.
CREATE FUNCTION $(NS).usp_batch_sync_broker_commission(p_run_date date)
RETURNS TABLE (brokers_changed integer, brokers_deactivated integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed integer;
    v_deactivated integer;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS tmp_tier (
        broker_id integer PRIMARY KEY,
        live_gwp numeric(19, 4) NOT NULL,
        new_pct numeric(5, 2) NOT NULL
    ) ON COMMIT DROP;
    TRUNCATE tmp_tier;

    INSERT INTO tmp_tier (broker_id, live_gwp, new_pct)
    SELECT
        p.broker_id,
        sum(p.annual_premium),
        CASE WHEN sum(p.annual_premium) >= 150000 THEN 15.00 WHEN sum(p.annual_premium) >= 75000 THEN 12.50 ELSE 10.00 END
    FROM $(NS).policy AS p
    WHERE p.status = 'ACTIVE' AND p.broker_id IS NOT NULL AND p.inception_date <= p_run_date
    GROUP BY p.broker_id;

    UPDATE $(NS).broker AS t
    SET commission_pct = s.new_pct, is_active = true
    FROM tmp_tier AS s
    WHERE t.broker_id = s.broker_id AND (t.commission_pct <> s.new_pct OR NOT t.is_active);
    GET DIAGNOSTICS v_changed = ROW_COUNT;

    UPDATE $(NS).broker AS t
    SET is_active = false
    WHERE t.is_active AND NOT EXISTS (SELECT 1 FROM tmp_tier AS s WHERE s.broker_id = t.broker_id);
    GET DIAGNOSTICS v_deactivated = ROW_COUNT;

    RETURN QUERY SELECT v_changed + v_deactivated, v_deactivated;
END;
$$;
