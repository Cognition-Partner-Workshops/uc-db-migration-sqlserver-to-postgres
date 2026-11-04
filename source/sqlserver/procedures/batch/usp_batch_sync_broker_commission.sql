-- Re-tier broker commission from live premium; deactivate brokers with no live book.
CREATE OR ALTER PROCEDURE dbo.usp_batch_sync_broker_commission
    @run_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @changes TABLE (
        merge_action NVARCHAR(10) NOT NULL,
        broker_id INT NOT NULL,
        old_pct DECIMAL(5, 2) NULL,
        new_pct DECIMAL(5, 2) NULL,
        is_active BIT NOT NULL
    );

    CREATE TABLE #tier (
        broker_id INT NOT NULL PRIMARY KEY,
        live_gwp MONEY NOT NULL,
        new_pct DECIMAL(5, 2) NOT NULL
    );

    INSERT INTO #tier (broker_id, live_gwp, new_pct)
    SELECT
        p.broker_id,
        SUM(p.annual_premium),
        CASE
            WHEN SUM(p.annual_premium) >= 150000 THEN 15.00
            WHEN SUM(p.annual_premium) >= 75000 THEN 12.50
            ELSE 10.00
        END
    FROM dbo.policy AS p
    WHERE p.status = 'ACTIVE' AND p.broker_id IS NOT NULL AND p.inception_date <= @run_date
    GROUP BY p.broker_id;

    MERGE dbo.broker AS t
    USING #tier AS s
        ON t.broker_id = s.broker_id
    WHEN MATCHED AND (t.commission_pct <> s.new_pct OR t.is_active = 0) THEN
        UPDATE SET commission_pct = s.new_pct, is_active = 1
    WHEN NOT MATCHED BY SOURCE AND t.is_active = 1 THEN
        UPDATE SET is_active = 0
    OUTPUT $action, inserted.broker_id, deleted.commission_pct, inserted.commission_pct, inserted.is_active
    INTO @changes (merge_action, broker_id, old_pct, new_pct, is_active);

    SELECT
        COUNT(*) AS brokers_changed,
        ISNULL(SUM(IIF(is_active = 0, 1, 0)), 0) AS brokers_deactivated
    FROM @changes;
END;
GO
