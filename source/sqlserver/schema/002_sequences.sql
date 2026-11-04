-- Business numbers come from sequences, surrogate keys from IDENTITY.
CREATE SEQUENCE dbo.seq_policy_number AS int START WITH 100001 INCREMENT BY 1 NO CYCLE CACHE 50;
GO
CREATE SEQUENCE dbo.seq_claim_number AS int START WITH 500001 INCREMENT BY 1 NO CYCLE CACHE 50;
GO
