-- Reference data lives in [ref]; transactional data in [dbo].
IF SCHEMA_ID(N'ref') IS NULL
    EXEC (N'CREATE SCHEMA ref AUTHORIZATION dbo');
GO
