-- dbo.usp_rate_quote. MONEY variables round to 4 dp on assignment.
CREATE FUNCTION $(NS).usp_rate_quote(
    p_product_code citext,
    p_country_code citext,
    p_sum_insured numeric,
    p_date_of_birth date,
    p_start_date date
)
RETURNS TABLE (
    product_code text,
    rated_age integer,
    age_loading numeric,
    net_premium numeric,
    premium_tax numeric,
    gross_premium numeric
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
    v_base_rate numeric;
    v_min_premium numeric;
    v_tax_rate numeric;
    v_years integer;
    v_age integer;
    v_loading numeric;
    v_net numeric;
    v_tax numeric;
BEGIN
    SELECT p.base_rate, p.min_premium INTO v_base_rate, v_min_premium
    FROM $(NS).product AS p
    WHERE p.product_code = p_product_code AND p.is_active;

    IF v_base_rate IS NULL THEN
        RAISE EXCEPTION 'Unknown or inactive product' USING ERRCODE = 'P0001', HINT = 'tsql:50100';
    END IF;

    SELECT c.premium_tax_rate INTO v_tax_rate FROM $(NS).country AS c WHERE c.country_code = p_country_code;

    IF v_tax_rate IS NULL THEN
        RAISE EXCEPTION 'Unknown country code' USING ERRCODE = 'P0001', HINT = 'tsql:50101';
    END IF;

    v_years := extract(YEAR FROM p_start_date)::integer - extract(YEAR FROM p_date_of_birth)::integer;
    v_age := v_years - CASE WHEN (p_date_of_birth + make_interval(years => v_years))::date > p_start_date THEN 1 ELSE 0 END;

    v_loading := CASE WHEN v_age < 25 THEN 0.2500 WHEN v_age >= 70 THEN 0.1500 ELSE 0 END;

    v_net := round(p_sum_insured * v_base_rate * (1 + v_loading), 4);
    v_net := CASE WHEN v_net < v_min_premium THEN v_min_premium ELSE v_net END;
    v_tax := round(v_net * v_tax_rate, 4);

    RETURN QUERY SELECT
        upper(p_product_code::text),
        v_age,
        v_loading,
        round(v_net, 2),
        round(v_tax, 2),
        round(v_net, 2) + round(v_tax, 2);
END;
$$;
