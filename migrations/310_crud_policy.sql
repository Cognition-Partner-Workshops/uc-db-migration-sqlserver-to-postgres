CREATE FUNCTION $(NS).usp_policy_create(
    p_policyholder_id integer,
    p_product_code citext,
    p_inception_date date,
    p_sum_insured numeric,
    p_annual_premium numeric,
    p_broker_code citext DEFAULT NULL,
    p_payment_frequency smallint DEFAULT 1,
    p_as_of timestamp DEFAULT NULL
)
RETURNS TABLE (
    policy_id integer,
    policy_number text,
    policyholder_id integer,
    broker_id integer,
    product_id integer,
    status text,
    inception_date date,
    expiry_date date,
    payment_frequency smallint,
    annual_premium numeric
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_now timestamp(3) := coalesce(p_as_of, now() AT TIME ZONE 'UTC');
    v_product_id integer;
    v_broker_id integer;
    v_policy_id integer;
BEGIN
    SELECT pr.product_id INTO v_product_id
    FROM $(NS).product AS pr
    WHERE pr.product_code = p_product_code AND pr.is_active;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'Unknown or inactive product' USING ERRCODE = 'P0001', HINT = 'tsql:50010';
    END IF;

    IF p_broker_code IS NOT NULL THEN
        SELECT b.broker_id INTO v_broker_id FROM $(NS).broker AS b WHERE b.broker_code = p_broker_code;
        IF v_broker_id IS NULL THEN
            RAISE EXCEPTION 'Unknown broker' USING ERRCODE = 'P0001', HINT = 'tsql:50011';
        END IF;
    END IF;

    INSERT INTO $(NS).policy (
        policyholder_id, broker_id, product_id, status, inception_date, expiry_date,
        payment_frequency, annual_premium, created_at
    )
    VALUES (
        p_policyholder_id, v_broker_id, v_product_id, 'ACTIVE', p_inception_date,
        (p_inception_date + interval '1 year' - interval '1 day')::date,
        p_payment_frequency, p_annual_premium, v_now
    )
    RETURNING policy.policy_id INTO v_policy_id;

    INSERT INTO $(NS).policy_version (
        policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium, change_reason, created_at
    )
    VALUES (v_policy_id, 1, p_inception_date, NULL, p_sum_insured, p_annual_premium, 'New business', v_now);

    RETURN QUERY
    SELECT
        p.policy_id, p.policy_number::text, p.policyholder_id, p.broker_id, p.product_id, p.status::text,
        p.inception_date, p.expiry_date, p.payment_frequency, p.annual_premium
    FROM $(NS).policy AS p
    WHERE p.policy_id = v_policy_id;
END;
$$;

CREATE FUNCTION $(NS).usp_policy_get(p_policy_number citext)
RETURNS TABLE (
    policy_id integer,
    policy_number text,
    status text,
    product_code text,
    product_name text,
    holder_name text,
    broker_name text,
    inception_date date,
    expiry_date date,
    version_no integer,
    sum_insured numeric,
    annual_premium numeric,
    coverage_count bigint,
    total_limit numeric,
    coverage_codes text
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        p.policy_id,
        p.policy_number::text,
        p.status::text,
        pr.product_code::text,
        pr.product_name::text,
        $(NS).fn_format_name(ph.first_name, ph.middle_name, ph.last_name),
        coalesce(b.broker_name, 'Direct')::text,
        p.inception_date,
        p.expiry_date,
        cv.version_no,
        cv.sum_insured,
        cv.annual_premium,
        cs.coverage_count,
        cs.total_limit,
        cs.coverage_codes
    FROM $(NS).policy AS p
    INNER JOIN $(NS).product AS pr ON p.product_id = pr.product_id
    INNER JOIN $(NS).policyholder AS ph ON p.policyholder_id = ph.policyholder_id
    LEFT JOIN $(NS).broker AS b ON p.broker_id = b.broker_id
    LEFT JOIN LATERAL (
        SELECT v.version_no, v.sum_insured, v.annual_premium
        FROM $(NS).policy_version AS v
        WHERE v.policy_id = p.policy_id
        ORDER BY v.effective_from DESC, v.version_no DESC
        LIMIT 1
    ) AS cv ON true
    LEFT JOIN LATERAL $(NS).tvf_policy_coverage_summary(p.policy_id) AS cs ON true
    WHERE p.policy_number = p_policy_number
$$;

CREATE FUNCTION $(NS).usp_policy_endorse(
    p_policy_id integer,
    p_effective_from date,
    p_sum_insured numeric,
    p_annual_premium numeric,
    p_change_reason text,
    p_as_of timestamp DEFAULT NULL
)
RETURNS TABLE (
    policy_id integer,
    version_no integer,
    effective_from date,
    sum_insured numeric,
    annual_premium numeric,
    change_reason text
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_now timestamp(3) := coalesce(p_as_of, now() AT TIME ZONE 'UTC');
    v_status text;
    v_policy_number text;
    v_next_version integer;
BEGIN
    SELECT p.status, p.policy_number INTO v_status, v_policy_number
    FROM $(NS).policy AS p
    WHERE p.policy_id = p_policy_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Policy not found' USING ERRCODE = 'P0001', HINT = 'tsql:50020';
    END IF;

    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Policy % is not active', v_policy_number USING ERRCODE = 'P0001', HINT = 'tsql:50000';
    END IF;

    SELECT max(v.version_no) + 1 INTO v_next_version
    FROM $(NS).policy_version AS v
    WHERE v.policy_id = p_policy_id;

    UPDATE $(NS).policy_version AS v
    SET effective_to = p_effective_from - 1
    WHERE v.policy_id = p_policy_id AND v.effective_to IS NULL;

    RETURN QUERY
    WITH ins AS (
        INSERT INTO $(NS).policy_version (
            policy_id, version_no, effective_from, effective_to, sum_insured, annual_premium, change_reason, created_at
        )
        VALUES (
            p_policy_id, v_next_version, p_effective_from, NULL, p_sum_insured, p_annual_premium, p_change_reason, v_now
        )
        RETURNING
            policy_version.policy_id, policy_version.version_no, policy_version.effective_from,
            policy_version.sum_insured, policy_version.annual_premium, policy_version.change_reason
    )
    SELECT ins.policy_id, ins.version_no, ins.effective_from, ins.sum_insured, ins.annual_premium,
        ins.change_reason::text
    FROM ins;

    UPDATE $(NS).policy AS p
    SET annual_premium = p_annual_premium, updated_at = v_now
    WHERE p.policy_id = p_policy_id;
END;
$$;
