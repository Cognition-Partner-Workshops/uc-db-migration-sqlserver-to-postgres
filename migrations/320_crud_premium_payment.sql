CREATE FUNCTION $(NS).usp_premium_payment_record(
    p_policy_id integer,
    p_amount numeric,
    p_method citext,
    p_paid_at timestamptz,
    p_schedule_id integer DEFAULT NULL,
    p_payer_iban text DEFAULT NULL,
    p_reference_text text DEFAULT NULL
)
RETURNS TABLE (
    policy_id integer,
    schedule_id integer,
    paid_at timestamptz,
    amount numeric,
    method text,
    reference_text text
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    -- MONEY parameters arrive with four decimals: round on entry like the legacy proc.
    v_amount numeric(19, 4) := p_amount;
BEGIN
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be positive' USING ERRCODE = 'P0001', HINT = 'tsql:50030';
    END IF;

    IF p_schedule_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM $(NS).premium_schedule AS s
        WHERE s.schedule_id = p_schedule_id AND s.policy_id = p_policy_id
    ) THEN
        RAISE EXCEPTION 'Installment does not belong to policy' USING ERRCODE = 'P0001', HINT = 'tsql:50031';
    END IF;

    RETURN QUERY
    WITH ins AS (
        INSERT INTO $(NS).premium_payment (policy_id, schedule_id, paid_at, amount, method, payer_iban, reference_text)
        VALUES (
            p_policy_id, p_schedule_id, p_paid_at, v_amount, upper(p_method),
            nullif(replace(p_payer_iban, ' ', ''), ''), coalesce(p_reference_text, '')
        )
        RETURNING
            premium_payment.policy_id, premium_payment.schedule_id, premium_payment.paid_at,
            premium_payment.amount, premium_payment.method, premium_payment.reference_text
    )
    SELECT ins.policy_id, ins.schedule_id, ins.paid_at, ins.amount, ins.method::text, ins.reference_text::text
    FROM ins;

    IF p_schedule_id IS NOT NULL THEN
        UPDATE $(NS).premium_schedule AS s
        SET paid_amount = s.paid_amount + v_amount,
            status = CASE WHEN s.paid_amount + v_amount >= s.amount_due THEN 'PAID' ELSE s.status END
        WHERE s.schedule_id = p_schedule_id;
    END IF;
END;
$$;
