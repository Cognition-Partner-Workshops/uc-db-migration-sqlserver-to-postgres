-- Build the installment plan for a policy. Installments are kept to the
-- fourth decimal (as finance books them); the last one absorbs the remainder
-- so the plan always adds up to the annual premium.
CREATE OR ALTER PROCEDURE dbo.usp_premium_schedule_build
    @policy_id INT,
    @commit BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @annual MONEY;
    DECLARE @frequency TINYINT;
    DECLARE @inception DATE;
    DECLARE @installment MONEY;
    DECLARE @step INT;
    DECLARE @n INT = 1;
    DECLARE @month_end BIT;

    SELECT @annual = annual_premium, @frequency = payment_frequency, @inception = inception_date
    FROM dbo.policy
    WHERE policy_id = @policy_id;

    IF @annual IS NULL
        THROW 50110, N'Policy not found', 1;

    IF EXISTS (SELECT 1 FROM dbo.premium_schedule WHERE policy_id = @policy_id)
        THROW 50111, N'Policy already has a premium schedule', 1;

    CREATE TABLE #plan (
        installment_no TINYINT NOT NULL PRIMARY KEY,
        due_date DATE NOT NULL,
        amount_due MONEY NOT NULL
    );

    SET @installment = @annual / @frequency;
    SET @step = 12 / @frequency;
    SET @month_end = IIF(@inception = EOMONTH(@inception), 1, 0);

    WHILE @n <= @frequency
    BEGIN
        INSERT INTO #plan (installment_no, due_date, amount_due)
        VALUES (
            @n,
            IIF(
                @month_end = 1,
                EOMONTH(DATEADD(MONTH, (@n - 1) * @step, @inception)),
                DATEADD(MONTH, (@n - 1) * @step, @inception)
            ),
            IIF(@n = @frequency, @annual - @installment * (@frequency - 1), @installment)
        );
        SET @n += 1;
    END;

    IF @commit = 1
        INSERT INTO dbo.premium_schedule (policy_id, installment_no, due_date, amount_due, paid_amount, status)
        SELECT @policy_id, installment_no, due_date, amount_due, 0, 'DUE'
        FROM #plan;

    SELECT installment_no, due_date, amount_due
    FROM #plan
    ORDER BY installment_no;
END;
GO
