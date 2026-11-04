# Cutover plan (text only)

Nothing in this repo touches AWS. This is how the lab's local steps map onto a production cutover to Amazon Aurora PostgreSQL 18.

## 1. Target build

- Aurora PostgreSQL cluster from `infra/terraform` (validated in CI, never applied here): engine `aurora-postgresql`, version 18.6, master credentials managed by AWS Secrets Manager (`manage_master_user_password`), encryption on, deletion protection on.
- Cluster parameter group `aurora-postgresql18`:
  - `timezone = UTC`: the legacy estate stores UTC (`SYSUTCDATETIME()`), and `timestamptz` output must not shift.
  - `shared_preload_libraries = pg_stat_statements`.
  - `rds.logical_replication = 0` while Aurora is only a target. Set it to 1 if Aurora later feeds a reverse-replication fallback.
- Extensions: `citext` and `pgcrypto` only, both supported on Aurora PostgreSQL.
- Apply `migrations/` with `$(NS)` replaced by the production schema name, **without** `900_load_from_raw.sql` and the `95x` triggers.

## 2. Collation decision

The SQL Server database uses `Latin1_General_100_CI_AS`. The target keeps the cluster default collation (`en_US.UTF-8` in RDS) and gets case-insensitivity through `citext` columns and parameters, so B-tree indexes and `LIKE` keep working. Nondeterministic ICU collations were rejected (see CONVERSION_PLAYBOOK.md). Accent sensitivity matches the source (`AS`). Sort order of accented names can differ between Windows and ICU/glibc collations; no business output in this estate depends on it, and reconcile orders by keys.

## 3. Data movement with AWS DMS

1. **Source prep (SQL Server)**: enable MS-CDC on the database and the 13 tables (`sys.sp_cdc_enable_db`, `sys.sp_cdc_enable_table`), or MS-Replication for tables with a primary key. Note: SQL Server Express has no SQL Server Agent, so it cannot run the CDC capture jobs. The production source must be Standard/Enterprise, which is the usual position for a real estate.
2. **DMS endpoints**: source with a read-only login equivalent to `migration_reader` (plus CDC rights); target with a dedicated DMS user. Credentials come from Secrets Manager.
3. **Task: full load + ongoing replication (CDC)**:
   - Table mappings `dbo.%` and `ref.%` → target schema, lower-case names.
   - LOB mode limited (no LOB columns over 32 KB in this estate).
   - Do not migrate `ROWVERSION` (`claim.row_ver`) or computed columns (`policyholder.full_name`); the target generates them.
   - Target table prep "do nothing": the tables already exist from `migrations/`.
4. **After full load**: run the equivalent of `reset_identities()`, then reconcile counts and checksums against a consistent snapshot (database snapshot or CDC LSN).
5. **Enable triggers** (`95x`) once CDC lag is near zero, so replicated history does not create audit rows twice.

## 4. Validation before switch

- DMS data validation on all tables.
- `verify/reconcile.py` against production copies: counts, checksums, business rules, routine parity on fixed inputs.
- Application smoke test on a read-only connection.

## 5. Switch

1. Freeze writes on SQL Server (application maintenance mode).
2. Wait for CDC lag 0; final reconcile on counts and checksums.
3. Stop the DMS task; `reset_identities()` again.
4. Point applications at the Aurora writer endpoint; nightly batch moves from SQL Server Agent to an external scheduler (EventBridge Scheduler + a small runner, or `pg_cron` on Aurora).
5. Keep SQL Server read-only for the fallback window.

## 6. Fallback

Before the switch, decide whether reverse replication (Aurora → SQL Server via DMS with `rds.logical_replication = 1`) is needed. Without it, fallback means replaying writes made since the switch.
