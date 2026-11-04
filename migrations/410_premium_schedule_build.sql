-- dbo.usp_premium_schedule_build. MONEY / integer truncates to 4 dp; the last
-- installment absorbs the remainder. Month-end inceptions stay on month ends.
CREATE FUNCTION $(NS).usp_premium_schedule_build(p_policy_id integer, p_commit boolean DEFAULT true)
RETURNS TABLE (installment_no smallint, due_date date, amount_due numeric)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_annual numeric;
    v_frequency integer;
    v_inception date;
    v_installment numeric;
    v_step integer;
    v_month_end boolean;
BEGIN
    SELECT p.annual_premium, p.payment_frequency, p.inception_date
    INTO v_annual, v_frequency, v_inception
    FROM $(NS).policy AS p
    WHERE p.policy_id = p_policy_id;

    IF v_annual IS NULL THEN
        RAISE EXCEPTION 'Policy not found' USING ERRCODE = 'P0001', HINT = 'tsql:50110';
    END IF;

    IF EXISTS (SELECT 1 FROM $(NS).premium_schedule AS s WHERE s.policy_id = p_policy_id) THEN
        RAISE EXCEPTION 'Policy already has a premium schedule' USING ERRCODE = 'P0001', HINT = 'tsql:50111';
    END IF;

    v_installment := trunc(v_annual / v_frequency, 4);
    v_step := 12 / v_frequency;
    v_month_end := v_inception = (date_trunc('month', v_inception) + interval '1 month - 1 day')::date;

    CREATE TEMP TABLE IF NOT EXISTS tmp_plan (
        installment_no smallint PRIMARY KEY,
        due_date date NOT NULL,
        amount_due numeric(19, 4) NOT NULL
    ) ON COMMIT DROP;
    TRUNCATE tmp_plan;

    INSERT INTO tmp_plan (installment_no, due_date, amount_due)
    SELECT
        n,
        CASE
            WHEN v_month_end
                THEN (date_trunc('month', v_inception + make_interval(months => (n - 1) * v_step)) + interval '1 month - 1 day')::date
            ELSE (v_inception + make_interval(months => (n - 1) * v_step))::date
        END,
        CASE WHEN n = v_frequency THEN v_annual - v_installment * (v_frequency - 1) ELSE v_installment END
    FROM generate_series(1, v_frequency) AS n;

    IF p_commit THEN
        INSERT INTO $(NS).premium_schedule (policy_id, installment_no, due_date, amount_due, paid_amount, status)
        SELECT p_policy_id, t.installment_no, t.due_date, t.amount_due, 0, 'DUE'
        FROM tmp_plan AS t;
    END IF;

    RETURN QUERY SELECT t.installment_no, t.due_date, t.amount_due::numeric FROM tmp_plan AS t ORDER BY t.installment_no;
END;
$$;
