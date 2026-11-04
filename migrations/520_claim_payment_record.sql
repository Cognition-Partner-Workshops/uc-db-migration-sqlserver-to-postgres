-- dbo.usp_claim_payment_record. RAISERROR texts are kept; ROW_COUNT is read
-- straight after the INSERT, before anything else can change it.
CREATE FUNCTION $(NS).usp_claim_payment_record(
    p_claim_id integer,
    p_reserve_type citext,
    p_amount numeric,
    p_payee_name text,
    p_payee_iban text DEFAULT NULL,
    p_paid_at timestamp(3) DEFAULT NULL
)
RETURNS TABLE (claim_id integer, reserve_type text, amount numeric, rows_written integer, outstanding_after numeric)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_status text;
    v_reserve numeric;
    v_paid numeric;
    v_rows integer;
BEGIN
    SELECT c.status INTO v_status FROM $(NS).claim AS c WHERE c.claim_id = p_claim_id;
    IF v_status IS NULL OR upper(v_status) NOT IN ('OPEN', 'REOPENED') THEN
        RAISE EXCEPTION 'Claim % is not open for payment', p_claim_id USING ERRCODE = 'P0001', HINT = 'tsql:50000';
    END IF;

    SELECT cr.amount INTO v_reserve
    FROM $(NS).claim_reserve AS cr
    WHERE cr.claim_id = p_claim_id AND cr.reserve_type = p_reserve_type;

    SELECT coalesce(sum(cp.amount), 0) INTO v_paid
    FROM $(NS).claim_payment AS cp
    WHERE cp.claim_id = p_claim_id AND cp.reserve_type = p_reserve_type;

    IF v_paid + p_amount > coalesce(v_reserve, 0) THEN
        RAISE EXCEPTION 'Payment exceeds the outstanding % reserve', p_reserve_type USING ERRCODE = 'P0001', HINT = 'tsql:50000';
    END IF;

    INSERT INTO $(NS).claim_payment (claim_id, reserve_type, paid_at, amount, payee_name, payee_iban)
    VALUES (p_claim_id, upper(p_reserve_type::text), p_paid_at, p_amount, p_payee_name, p_payee_iban);
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    RETURN QUERY SELECT p_claim_id, upper(p_reserve_type::text), p_amount, v_rows, coalesce(v_reserve, 0) - v_paid - p_amount;
END;
$$;
