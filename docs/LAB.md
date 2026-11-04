# Lab: migrate the rest of the estate with Devin

You start from `main`: the SQL Server 2022 Express estate is seeded, Phase 1 (schema, functions, views, CRUD) is converted to PostgreSQL 18, and reconcile shows Phase 2 as **NOT CONVERTED**.

Setup, once per machine:

```bash
make install docker-up seed
make build reconcile NS=dev     # PASS 33, FAIL 0, NOT CONVERTED 18
```

Give each exercise its own namespace (`NS=lab_<yourname>`) and branch.

## Exercise 1: estate inventory

> Inventory the SQL Server estate in `source/sqlserver/`. For every procedure, function, view and trigger, list the T-SQL constructs it uses, the objects it calls or touches, and whether it is already converted in `migrations/`. Compare your inventory with `docs/SQLSERVER_TO_POSTGRES_MIGRATION_MAP.md` and tell me about any discrepancy. Then propose the order to convert the Phase 2 objects, with reasons. Don't change any files.

What to look for: dependency order (claims procedures call each other and fire triggers), which objects use `MERGE`, dynamic SQL, cursors, temp tables or `FOR JSON`.

## Exercise 2: convert the claims procedures and prove parity

> Convert the four Phase 2 claims procedures (`usp_claim_open`, `usp_claim_reserve_set`, `usp_claim_payment_record`, `usp_claim_close`) from `source/sqlserver/procedures/claims/` to PostgreSQL in `migrations/`, using the file names in the migration map and the rules in `AGENTS.md`. Build into `NS=lab_claims`, run `make reconcile NS=lab_claims` and `make functional NS=lab_claims`, and iterate until all four are PASS and the functional test runs the full scenario through "close claim" with no other control changing status. Explain every semantic difference you had to handle, and open a PR with the reconcile summary.

Done when: the four claims controls are PASS, nothing else regresses, and the functional test compares the post-claim state on both engines.

Stretch: the three audit triggers (`95x`), then reporting and batch.

## Exercise 3: explain and fix the naive conversion

> Run `make reconcile-naive`. One control fails. Explain from the report and the T-SQL source exactly why the naive PostgreSQL version of that object returns different rows. Name every T-SQL semantic it gets wrong and show a minimal SQL example of each on both engines. Then write a correct conversion in `migrations/` (not in `naive_conversion/`), build it into its own namespace and show it reconciles. Don't edit the seed, the controls or the normalisation rules.

Done when: the explanation names each behaviour difference with a reproduction, and the corrected object is PASS in your namespace while `make reconcile-naive` still fails (the naive file is a fixture).
