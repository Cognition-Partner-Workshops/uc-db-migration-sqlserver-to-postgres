CREATE TABLE dbo.premium_schedule (
    schedule_id INT IDENTITY (1, 1) NOT NULL CONSTRAINT pk_premium_schedule PRIMARY KEY,
    policy_id INT NOT NULL CONSTRAINT fk_schedule_policy REFERENCES dbo.policy (policy_id),
    installment_no TINYINT NOT NULL,
    due_date DATE NOT NULL,
    amount_due MONEY NOT NULL,
    paid_amount MONEY NOT NULL CONSTRAINT df_schedule_paid DEFAULT (0),
    status VARCHAR(10) NOT NULL
        CONSTRAINT ck_schedule_status CHECK (status IN ('DUE', 'PAID', 'OVERDUE', 'CANCELLED')),
    CONSTRAINT uq_schedule_installment UNIQUE (policy_id, installment_no)
);
GO
-- Filtered index: collections only ever look at open installments.
CREATE INDEX ix_premium_schedule_open
ON dbo.premium_schedule (due_date) INCLUDE (policy_id, amount_due, paid_amount)
WHERE status IN ('DUE', 'OVERDUE');
GO
