-- DATEDIFF(MONTH, a, b) counts month boundaries crossed, not elapsed months:
-- compute it from year/month parts instead of age().
CREATE FUNCTION $(NS).fn_months_between(p_from_date date, p_to_date date)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT ((extract(YEAR FROM p_to_date) * 12 + extract(MONTH FROM p_to_date))
          - (extract(YEAR FROM p_from_date) * 12 + extract(MONTH FROM p_from_date)))::integer
$$;

-- MONEY division keeps four decimals by truncation; numeric would round.
CREATE FUNCTION $(NS).fn_pro_rata(p_amount numeric, p_days integer, p_period_days integer)
RETURNS numeric(19, 4)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN p_period_days IS NULL OR p_period_days = 0 THEN NULL
        ELSE trunc(p_amount * p_days / p_period_days, 4)
    END
$$;

-- '+' with a NULL operand yields NULL in T-SQL and || does the same here;
-- the middle name is wrapped so a missing one disappears cleanly.
CREATE FUNCTION $(NS).fn_format_name(p_first_name text, p_middle_name text, p_last_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT rtrim(ltrim(p_first_name)) || ' '
        || coalesce(nullif(rtrim(ltrim(p_middle_name)), '') || ' ', '')
        || rtrim(ltrim(p_last_name))
$$;

CREATE FUNCTION $(NS).tvf_policy_coverage_summary(p_policy_id integer)
RETURNS TABLE (
    policy_id integer,
    coverage_count bigint,
    total_limit numeric,
    total_deductible numeric,
    coverage_codes text
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        c.policy_id,
        count(*),
        sum(c.limit_amount),
        sum(c.deductible),
        string_agg(upper(c.coverage_code::text), ',' ORDER BY upper(c.coverage_code::text))
    FROM $(NS).coverage AS c
    WHERE c.policy_id = p_policy_id
    GROUP BY c.policy_id
$$;
