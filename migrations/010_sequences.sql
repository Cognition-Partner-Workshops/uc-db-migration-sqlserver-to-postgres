-- Business-number sequences (SQL Server CACHE 50 -> PostgreSQL CACHE 1 default;
-- gaps are acceptable in both engines). Restarted after the data load.
CREATE SEQUENCE $(NS).seq_policy_number AS integer START WITH 100001 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE $(NS).seq_claim_number AS integer START WITH 500001 INCREMENT BY 1 NO CYCLE;
