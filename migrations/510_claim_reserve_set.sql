-- dbo.usp_claim_reserve_set. MERGE stays MERGE (PG15+); the action is worked
-- out before the MERGE because RETURNING merge_action() needs PG17. "merge_action" is quoted: reserved in PG17+.
CREATE FUNCTION $(NS).usp_claim_reserve_set(
    p_claim_id integer,
    p_reserve_type citext,
    p_amount numeric,
    p_set_by text,
    p_as_of timestamp(3) DEFAULT NULL
)
RETURNS TABLE ("merge_action" text, reserve_type text, old_amount numeric, new_amount numeric)  -- noqa: RF06
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_now timestamp(3) := coalesce(p_as_of, now() AT TIME ZONE 'UTC');
    v_paid numeric;
    v_old numeric;
    v_action text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM $(NS).claim AS c WHERE c.claim_id = p_claim_id AND c.status IN ('OPEN', 'REOPENED')
    ) THEN
        RAISE EXCEPTION 'Claim is not open' USING ERRCODE = 'P0001', HINT = 'tsql:50210';
    END IF;

    SELECT coalesce(sum(cp.amount), 0) INTO v_paid
    FROM $(NS).claim_payment AS cp
    WHERE cp.claim_id = p_claim_id AND cp.reserve_type = p_reserve_type;

    IF p_amount < v_paid THEN
        RAISE EXCEPTION 'Reserve cannot be lower than the amount already paid' USING ERRCODE = 'P0001', HINT = 'tsql:50211';
    END IF;

    SELECT cr.amount INTO v_old
    FROM $(NS).claim_reserve AS cr
    WHERE cr.claim_id = p_claim_id AND cr.reserve_type = p_reserve_type
    FOR UPDATE;
    v_action := CASE WHEN FOUND THEN 'UPDATE' ELSE 'INSERT' END;

    MERGE INTO $(NS).claim_reserve AS t
    USING (SELECT p_claim_id AS claim_id, upper(p_reserve_type::text)::citext AS reserve_type, p_amount AS amount) AS s
        ON t.claim_id = s.claim_id AND t.reserve_type = s.reserve_type
    WHEN MATCHED THEN
        UPDATE SET amount = s.amount, set_at = v_now, set_by = p_set_by
    WHEN NOT MATCHED THEN
        INSERT (claim_id, reserve_type, amount, set_at, set_by)
        VALUES (s.claim_id, s.reserve_type, s.amount, v_now, p_set_by);

    RETURN QUERY SELECT v_action, upper(p_reserve_type::text), v_old, p_amount;
END;
$$;
