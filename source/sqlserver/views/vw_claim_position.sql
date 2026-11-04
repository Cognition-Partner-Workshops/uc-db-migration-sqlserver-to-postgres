-- Reserve, paid and outstanding position per claim.
CREATE OR ALTER VIEW dbo.vw_claim_position
AS
SELECT
    c.claim_id,
    c.claim_number,
    c.policy_id,
    c.status,
    c.loss_date,
    COALESCE(r.reserve_total, 0) AS reserve_total,
    COALESCE(pay.paid_total, 0) AS paid_total,
    COALESCE(r.reserve_total, 0) - COALESCE(pay.paid_total, 0) AS outstanding,
    pay.last_paid_at
FROM dbo.claim AS c
OUTER APPLY (
    SELECT SUM(cr.amount) AS reserve_total
    FROM dbo.claim_reserve AS cr
    WHERE cr.claim_id = c.claim_id
) AS r
OUTER APPLY (
    SELECT
        SUM(cp.amount) AS paid_total,
        MAX(cp.paid_at) AS last_paid_at
    FROM dbo.claim_payment AS cp
    WHERE cp.claim_id = c.claim_id
) AS pay;
GO
