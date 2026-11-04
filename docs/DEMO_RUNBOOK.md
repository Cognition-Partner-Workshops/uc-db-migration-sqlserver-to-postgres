# Demo runbook: live SQL Server → PostgreSQL 18 migration with Devin

About 30 minutes. The audience sees a real SQL Server estate, a reconciliation report that will not lie, and Devin converting legacy T-SQL live until the report goes green.

## Before the session (T−1 day)

1. Start a Devin session on this repo (the environment blueprint installs ODBC Driver 18, the Python packages, and starts both engines).
2. In the session: `make docker-up seed build reconcile NS=dev`. Expect **PASS 33, FAIL 0, NOT CONVERTED 18** (`work/reconcile/report.md`).
3. `make reconcile-naive`: expect exactly one FAIL, `dbo.usp_report_claims_ageing`.
4. Check that `rehearsal/phase2` builds green: `git switch rehearsal/phase2 && make build reconcile functional NS=rehearsal`, then `git switch main`. This is your fallback.
5. Open in tabs: `source/sqlserver/procedures/claims/usp_claim_reserve_set.sql`, `docs/SQLSERVER_TO_POSTGRES_MIGRATION_MAP.md`, `work/reconcile/report.md`.

## Live flow

| Min | Beat | What you do / say |
|---|---|---|
| 0–3 | The estate | Show `source/sqlserver/`: 13 tables, 21 procedures, `MERGE`, cursors, dynamic SQL, triggers, `FOR JSON`. `make coverage`: 38/38 constructs. "This is a typical insurer's SQL Server back office." |
| 3–6 | Phase 1 already done | `make reconcile NS=dev`. Walk the report: counts and per-column checksums per table, then every function, view and CRUD procedure run on fixed inputs on both engines. Phase 2 shows NOT CONVERTED. "NOT CONVERTED is not PASS: the harness never claims what has not been proven." |
| 6–9 | Why a harness | `make reconcile-naive`. The plausible-looking ageing report fails: claims land in the wrong age band. "A line-by-line conversion compiles, runs and is wrong. Only a parity harness catches it." |
| 9–25 | Live conversion | Paste the Exercise 2 prompt from `docs/LAB.md` (claims procedures, `NS=live`). While Devin works, narrate: it reads the T-SQL, the migration map and `AGENTS.md`, writes `migrations/5xx`, builds, reconciles, reads the FAIL diffs and fixes the conversion, never the controls. |
| 25–28 | Proof | `make reconcile NS=live`: four claims controls go from NOT CONVERTED to PASS. `make functional NS=live`: create policy → endorse → pay → open claim → close claim compared on both engines. Show Devin's PR. |
| 28–30 | Wrap | The full answer is on `rehearsal/phase2` (all 18 Phase 2 objects PASS). Cutover with DMS full load + CDC is in `docs/CUTOVER.md`; Aurora target in `infra/terraform` (validated, never applied). |

## If something goes wrong

- **Devin is slow or stuck on one procedure**: say "this is the hard one, here's what it found so far", then `git switch rehearsal/phase2 && make build reconcile NS=rehearsal` and show the finished state.
- **A container is down**: `make docker-up` (healthchecks wait for both engines), then `make seed` (about 1 minute).
- **Port clash on 55432**: `export PGPORT=55433 && make docker-up` (compose and the scripts both read `PGPORT`).
- **Someone asks about Babelfish**: an Aurora option that runs T-SQL as-is over TDS; this demo targets native PostgreSQL so the estate stops depending on T-SQL.
- **Someone asks about AWS SCT**: not run here; see `docs/AWS_SCT_COMPARISON.md` for what to check in its output.

## Reset between runs

```bash
make demo-down NS=live      # drop the live namespace; estate, raw and dev remain
make seed                   # optional: reseed from the fixed seed (deterministic)
```
