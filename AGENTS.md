# AGENTS.md

SQL Server 2022 Express → PostgreSQL 18 (Aurora PostgreSQL-compatible) migration lab for a synthetic European P&C insurer.

## Layout

- `source/sqlserver/` – the legacy T-SQL estate (tables, sequences, functions, views, procedures, triggers). Treat as read-only legacy code.
- `seed/` – local engine helpers: deploy the estate, generate the deterministic synthetic data, create the read-only `migration_reader` login, copy tables to PostgreSQL `raw`, build a namespace, run the nightly batch.
- `migrations/` – the PostgreSQL target, numbered SQL files run in name order with `$(NS)` replaced by the namespace.
  `0xx` tables/sequences, `1xx` functions, `2xx` views, `3xx` CRUD procedures. Phase 2 goes in `4xx` rating, `5xx` claims, `6xx` reporting, `7xx` batch. `900_load_from_raw.sql` loads the data; triggers go in `95x`, after the load, the same order as a DMS full load followed by enabling triggers.
- `naive_conversion/` – a deliberately wrong conversion used by `make reconcile-naive`. Do not "fix" it in place.
- `verify/` – `reconcile.py` (parity harness), `controls.py` (fixed inputs per object), `normalize.py` (comparison rules), `functional_tests.py`, `construct_coverage.py`.
- `docs/` – migration map, construct map, conversion playbook, runbook, cutover, SCT comparison, lab prompts.

## Commands

```bash
make docker-up              # SQL Server 2022 Express on :1433, PostgreSQL 18.6 on :55432
make seed                   # deploy legacy estate + synthetic data + copy to PostgreSQL raw
make build NS=dev           # build namespace dev from migrations/
make reconcile NS=dev       # report in work/reconcile/report.md, exit 1 on any FAIL
make functional NS=dev      # end-to-end policy/claim scenario on both engines
make reconcile-naive        # planted naive conversion, expected to FAIL
make batch NS=dev           # nightly batch (rolled back unless COMMIT=1)
make coverage lint          # construct coverage, sqlfluff/ruff/yamllint
make ci NS=dev              # what CI runs after seed
```

Use your own namespace per branch or session (`NS=claims_<you>`), so parallel runs never collide.

## Converting a legacy object

1. Read the T-SQL in `source/sqlserver/` and its row in `docs/SQLSERVER_TO_POSTGRES_MIGRATION_MAP.md`.
2. Follow `docs/CONVERSION_PLAYBOOK.md` and `docs/CONSTRUCT_MAP.md`: procedures become PL/pgSQL functions `RETURNS TABLE` with `p_`-prefixed parameters, code-like parameters are `citext`, `MONEY` arithmetic keeps four decimals.
3. Put the PostgreSQL file in the right numbered range in `migrations/`, keep the legacy object name.
4. `make build NS=<ns> && make reconcile NS=<ns>`; the object must move from NOT CONVERTED to PASS and nothing else may change.

## Rules

- **Never edit seed, golden, or reconcile controls to make a FAIL pass.** That covers `seed/`, `verify/controls.py`, `verify/normalize.py` and `verify/reconcile.py`. A FAIL means the conversion is wrong: fix the migration.
- **Never point at a non-local SQL Server.** `seed/db.py` refuses hosts other than the local container; do not change that or add credentials for any other server.
- Keep the target Aurora PostgreSQL-compatible: only `citext`, `pgcrypto`, `pg_trgm` and `tablefunc` extensions, and no PostgreSQL 18-only syntax.
- Do not change `source/sqlserver/`: it is the system being migrated.
- Terraform under `infra/terraform` is validated only. Never run `terraform plan` or `apply`.
