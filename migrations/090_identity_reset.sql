-- After an explicit-key load, move every identity past the loaded maximum and
-- restart the business-number sequences after the highest number in use.
CREATE FUNCTION $(NS).reset_identities()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    v_max bigint;
BEGIN
    FOR r IN
        SELECT c.table_name, c.column_name
        FROM information_schema.columns AS c
        WHERE c.table_schema = '$(NS)' AND c.is_identity = 'YES'
    LOOP
        EXECUTE format('SELECT coalesce(max(%I), 0) FROM %I.%I', r.column_name, '$(NS)', r.table_name) INTO v_max;
        PERFORM setval(pg_get_serial_sequence(format('%I.%I', '$(NS)', r.table_name), r.column_name),
            greatest(v_max, 1), v_max > 0);
    END LOOP;
    SELECT coalesce(max(substr(policy_number::text, 2)::bigint), 100000) INTO v_max FROM $(NS).policy;
    PERFORM setval('$(NS).seq_policy_number', v_max);
    SELECT coalesce(max(substr(claim_number::text, 2)::bigint), 500000) INTO v_max FROM $(NS).claim;
    PERFORM setval('$(NS).seq_claim_number', v_max);
END;
$$;
