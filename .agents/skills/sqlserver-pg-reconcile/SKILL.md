---
name: sqlserver-pg-reconcile
description: Convert a legacy T-SQL object from source/sqlserver to PostgreSQL 18 in migrations/ and prove parity with the reconcile harness. Use when asked to convert, migrate or fix a procedure, function, view or trigger in this repo, or to explain a reconcile FAIL.
---

# Convert a T-SQL object and prove parity

## Before you start

- Engines up and seeded: `make docker-up seed` (idempotent; reseeds from the fixed seed).
- Pick a namespace for your work, e.g. `NS=claims_demo`. Never reuse `dev` or `naive` for experiments.
- Baseline: `make build NS=$NS && make reconcile NS=$NS`. Note which objects are NOT CONVERTED.

## Convert

1. Read the legacy object and every object it calls. Check `docs/SQLSERVER_TO_POSTGRES_MIGRATION_MAP.md` for its target file and phase.
2. Look up each construct in `docs/CONSTRUCT_MAP.md` and read its Risk column; follow `docs/CONVERSION_PLAYBOOK.md` for signatures, errors, transactions and types. Replicate the legacy behaviour exactly, including behaviour that looks like a bug: reconcile compares results, state and error text.
3. Write the file in the numbered range from `AGENTS.md`, using `$(NS).` for every object reference.

## Prove

```bash
make build NS=$NS
make reconcile NS=$NS        # work/reconcile/report.md
make functional NS=$NS
make lint
```

The converted object must be PASS, and every other control must keep its status. When a control FAILs, read the diff in the report (`sqlserver only:` / `postgres only:` rows), find the semantic difference and fix the migration.

## Never

- Edit `seed/`, `verify/controls.py`, `verify/normalize.py` or `verify/reconcile.py` to make a FAIL pass.
- Point `SQLSERVER_HOST` at anything but the local container.
- Change `source/sqlserver/`.
