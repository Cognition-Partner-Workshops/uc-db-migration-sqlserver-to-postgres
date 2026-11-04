# Conversion playbook

How every object in this repo was converted, and how to convert the Phase 2 objects the same way. The construct-level detail is in [CONSTRUCT_MAP.md](CONSTRUCT_MAP.md).

## 1. Order of work

1. **Schema first** (tables, sequences, indexes): Phase 1, `0xx`.
2. **Load from `raw`** (`900_load_from_raw.sql`) and reset identities. Reconcile counts and per-column checksums before any code moves.
3. **Leaf code**: scalar functions, the TVF and views (`1xx`, `2xx`), because procedures call them.
4. **CRUD procedures** (`3xx`): small, write paths with clear state to compare.
5. **Phase 2**: rating (`4xx`), claims (`5xx`), reporting (`6xx`), batch (`7xx`), then triggers (`95x`, after the load).

One object (or one tight group) per commit; `make build reconcile NS=<ns>` after each one.

## 2. Type decisions

| SQL Server | PostgreSQL | Why |
|---|---|---|
| `MONEY` | `numeric(19,4)` | Same scale and range. PostgreSQL `money` depends on `lc_monetary` and is not portable. Where legacy code divides MONEY, wrap in `trunc(x, 4)` to keep MONEY's truncation. |
| `UNIQUEIDENTIFIER` | `uuid` | Native 16-byte type; `gen_random_uuid()` replaces `NEWID()`. Text output is lower case (SQL Server prints upper case); reconcile normalises case. |
| `Latin1_General_100_CI_AS` (case-insensitive) | `citext` on code/name/e-mail columns **and on routine parameters** | Keeps legacy lookup semantics with ordinary B-tree indexes. Nondeterministic ICU collations were rejected: they block `LIKE` and are harder to reason about across Aurora versions. A `citext` column compared with a `text` value is case-sensitive, so parameters must be `citext` too. |
| `DATETIMEOFFSET` | `timestamptz` | Stores an instant in UTC. The original offset is not kept; none of the estate reads it back. If an application needs it, add an `offset_minutes smallint` column. |
| `DATETIME2(3)` | `timestamp(3)` | Same precision; values are UTC by convention (`SYSUTCDATETIME()`). |
| `BIT` | `boolean` | |
| `TINYINT` | `smallint` | PostgreSQL has no 1-byte integer. |
| `ROWVERSION` | not migrated | `xmin` serves optimistic concurrency. |
| `NVARCHAR(n)` | `text` / `citext` + `CHECK` where length is a business rule | `varchar(n)` adds no storage benefit; keep `varchar(n)` where truncation semantics matter. |

## 3. Routine signatures

- A procedure that returns a result set becomes `CREATE FUNCTION $(NS).usp_x(p_a ..., p_b ...) RETURNS TABLE (...)`, called as `SELECT * FROM $(NS).usp_x(...)`. Keep the legacy name so the migration map stays 1:1.
- Parameter `@policy_id` becomes `p_policy_id`; output columns keep the legacy column names. Use `#variable_conflict use_column` when an output column shares a name with a table column.
- Code-like parameters (product, broker, country, coverage, cause, reserve type, payment method, policy number) are `citext`.
- Default parameter values stay as `DEFAULT`.
- `OUTPUT` parameters become extra output columns.

## 4. Errors

Legacy code raises `THROW 5xxxx, N'message', 1`. The target raises:

```sql
RAISE EXCEPTION 'Unknown country code' USING ERRCODE = 'P0001', DETAIL = '50001';
```

The message text must be identical; reconcile compares it for every error-path case. The SQL Server error number goes into `DETAIL`.

## 5. Transactions

SQL Server procedures open `BEGIN TRAN` with `XACT_ABORT ON` and commit inside. PostgreSQL functions run inside the caller's transaction: an exception rolls the whole call back, which matches `XACT_ABORT ON`. Do not use `COMMIT` inside routines; the batch driver commits.

## 6. Set-based logic

- `MERGE` stays `MERGE` (PostgreSQL 15+). Avoid PostgreSQL 17's `RETURNING merge_action()` so the code runs on every supported Aurora PostgreSQL major version.
- Cursors become `FOR rec IN ... LOOP` or, better, one set-based statement where the legacy cursor only accumulates counts.
- Temp tables become CTEs, or `CREATE TEMP TABLE ... ON COMMIT DROP` when the data is reused.
- Dynamic SQL becomes `RETURN QUERY EXECUTE format('... %I ...', ident) USING value`.

## 7. Triggers

T-SQL triggers fire once per statement with `inserted` / `deleted` pseudo-tables. Convert to:

```sql
CREATE TRIGGER trg_x AFTER UPDATE ON $(NS).t
REFERENCING OLD TABLE AS deleted NEW TABLE AS inserted
FOR EACH STATEMENT EXECUTE FUNCTION $(NS).trg_x_fn();
```

and keep the body set-based. Create triggers after the load (`95x`) so historical rows do not produce audit records.

## 8. Proving parity

- `make reconcile NS=<ns>` compares counts, per-column ordered checksums, every function/view/procedure on fixed inputs (results, error text and resulting state) and business rules. Normalisation rules are in `verify/normalize.py` and printed at the top of the report.
- `make functional NS=<ns>` runs create policy → endorse → pay premium → open claim → close claim on both engines and compares the resulting rows.
- A FAIL is a conversion bug. Do not change seed data, controls or normalisation to make it pass.
