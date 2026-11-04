-- Aurora PostgreSQL-supported extensions only. citext gives the legacy
-- case-insensitive (accent-sensitive) comparison semantics on code, name and
-- email columns; pgcrypto is kept for digest() in reconciliation helpers.
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
