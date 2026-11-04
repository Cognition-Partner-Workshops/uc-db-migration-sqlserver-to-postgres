-- dbo.usp_claim_close. ROWVERSION is replaced by xmin for optimistic concurrency.
CREATE FUNCTION $(NS).usp_claim_close(
    p_claim_id integer,
    p_expected_xmin xid DEFAULT NULL,
    p_as_of timestamp(0) DEFAULT NULL
)
RETURNS TABLE (claim_id integer, claim_number text, status text, closed_at timestamp)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_now timestamp(0) := coalesce(p_as_of, now() AT TIME ZONE 'UTC');
    v_rows integer;
BEGIN
    UPDATE $(NS).claim AS c
    SET status = 'CLOSED', closed_at = v_now
    WHERE c.claim_id = p_claim_id
        AND c.status IN ('OPEN', 'REOPENED')
        AND (p_expected_xmin IS NULL OR c.xmin = p_expected_xmin);
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Claim is not open or was changed by another user' USING ERRCODE = 'P0001', HINT = 'tsql:50230';
    END IF;

    UPDATE $(NS).claim_reserve AS r
    SET amount = coalesce(p.paid, 0), set_at = v_now, set_by = 'claims.close'
    FROM $(NS).claim_reserve AS r2
    LEFT JOIN LATERAL (
        SELECT sum(cp.amount) AS paid
        FROM $(NS).claim_payment AS cp
        WHERE cp.claim_id = r2.claim_id AND cp.reserve_type = r2.reserve_type
    ) AS p ON true
    WHERE r2.reserve_id = r.reserve_id AND r.claim_id = p_claim_id;

    RETURN QUERY
    SELECT c.claim_id, c.claim_number::text, c.status::text, c.closed_at::timestamp
    FROM $(NS).claim AS c
    WHERE c.claim_id = p_claim_id;
END;
$$;
