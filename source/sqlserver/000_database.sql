-- Database bootstrap. Executed against [master] by seed/deploy_source.py.
-- The database uses a case-insensitive, accent-sensitive default collation,
-- as the legacy back office always has. Every string comparison, join, GROUP BY
-- and CHECK constraint in this estate inherits it.
IF DB_ID(N'$(DB)') IS NULL
    CREATE DATABASE [$(DB)] COLLATE Latin1_General_100_CI_AS;
GO
ALTER DATABASE [$(DB)] SET RECOVERY SIMPLE;
GO
