-- One row per policy, one column per standard coverage limit.
CREATE OR ALTER VIEW dbo.vw_policy_coverage_pivot
AS
SELECT
    pvt.policy_id,
    pvt.[TPL] AS tpl_limit,
    pvt.[FIRE] AS fire_limit,
    pvt.[THEFT] AS theft_limit,
    pvt.[GLASS] AS glass_limit,
    pvt.[FLOOD] AS flood_limit
FROM (
    SELECT
        c.policy_id,
        c.coverage_code,
        c.limit_amount
    FROM dbo.coverage AS c
) AS src
PIVOT (
    SUM(limit_amount) FOR coverage_code IN ([TPL], [FIRE], [THEFT], [GLASS], [FLOOD])
) AS pvt;
GO
