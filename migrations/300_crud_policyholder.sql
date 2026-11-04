-- T-SQL procedures that return a result set become PL/pgSQL functions
-- RETURNS TABLE; the caller owns the transaction. Code-like parameters are
-- citext so lookups keep the legacy case-insensitive behaviour.
CREATE FUNCTION $(NS).usp_policyholder_create(
    p_first_name text,
    p_last_name text,
    p_date_of_birth date,
    p_iban text,
    p_address_line text,
    p_postcode text,
    p_city text,
    p_country_code citext,
    p_middle_name text DEFAULT NULL,
    p_email citext DEFAULT NULL,
    p_phone text DEFAULT NULL
)
RETURNS TABLE (
    policyholder_id integer,
    first_name text,
    middle_name text,
    last_name text,
    full_name text,
    date_of_birth date,
    email text,
    iban text,
    city text,
    country_code text
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_id integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM $(NS).country AS c WHERE c.country_code = p_country_code) THEN
        RAISE EXCEPTION 'Unknown country code' USING ERRCODE = 'P0001', HINT = 'tsql:50001';
    END IF;

    IF p_email IS NOT NULL AND EXISTS (SELECT 1 FROM $(NS).policyholder AS ph WHERE ph.email = p_email) THEN
        RAISE EXCEPTION 'A policyholder with this email already exists' USING ERRCODE = 'P0001', HINT = 'tsql:50002';
    END IF;

    INSERT INTO $(NS).policyholder (
        first_name, middle_name, last_name, date_of_birth, email, phone,
        iban, address_line, postcode, city, country_code
    )
    VALUES (
        p_first_name, p_middle_name, p_last_name, p_date_of_birth, p_email, p_phone,
        replace(upper(p_iban), ' ', ''), p_address_line, p_postcode, p_city, upper(p_country_code)
    )
    RETURNING policyholder.policyholder_id INTO v_id;

    RETURN QUERY
    SELECT
        ph.policyholder_id, ph.first_name::text, ph.middle_name::text, ph.last_name::text, ph.full_name,
        ph.date_of_birth, ph.email::text, ph.iban::text, ph.city::text, ph.country_code::text
    FROM $(NS).policyholder AS ph
    WHERE ph.policyholder_id = v_id;
END;
$$;

CREATE FUNCTION $(NS).usp_policyholder_get(
    p_policyholder_id integer DEFAULT NULL,
    p_email citext DEFAULT NULL
)
RETURNS TABLE (
    policyholder_id integer,
    external_ref uuid,
    display_name text,
    date_of_birth date,
    email text,
    iban text,
    postcode text,
    city text,
    country_name text,
    policy_count bigint
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        ph.policyholder_id,
        ph.external_ref,
        $(NS).fn_format_name(ph.first_name, ph.middle_name, ph.last_name),
        ph.date_of_birth,
        ph.email::text,
        ph.iban::text,
        ph.postcode::text,
        ph.city::text,
        c.country_name::text,
        coalesce(pc.policy_count, 0)
    FROM $(NS).policyholder AS ph
    INNER JOIN $(NS).country AS c ON ph.country_code = c.country_code
    LEFT JOIN LATERAL (
        SELECT count(*) AS policy_count
        FROM $(NS).policy AS p
        WHERE p.policyholder_id = ph.policyholder_id
    ) AS pc ON true
    WHERE (p_policyholder_id IS NULL OR ph.policyholder_id = p_policyholder_id)
        AND (p_email IS NULL OR ph.email = p_email)
        AND (p_policyholder_id IS NOT NULL OR p_email IS NOT NULL)
$$;
