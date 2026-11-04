# AWS SCT comparison

**AWS Schema Conversion Tool (SCT) was not run here.** This page explains where SCT would fit and what to compare when you run it against this estate. Nothing below is SCT output.

## Where SCT fits

AWS SCT (and the DMS Schema Conversion feature in the console) reads the SQL Server catalog, converts DDL and T-SQL to PostgreSQL, and produces an assessment report that sorts objects into "converted automatically", "simple actions" and "complex actions". It is a good first pass for tables, indexes, sequences and straightforward routines.

## What to check in its output

Run SCT against the local `pc_insurance` database, write its PostgreSQL output to a namespace and reconcile it like any other conversion:

```bash
# after applying SCT's DDL/code to schema sct (replace dbo/ref with sct)
make reconcile NS=sct
```

Areas where any automated converter needs a human, and where this harness has controls:

| Area | Why automated conversion needs review | Control |
|---|---|---|
| Case-insensitive collation | Converters keep `varchar`/`text`; lookups become case-sensitive | lower-case code cases in the CRUD, rating, claims and reporting controls |
| `MONEY` arithmetic | Mapped to `numeric`, so division rounds instead of truncating | `fn_pro_rata`, `usp_premium_schedule_build`, schedule-total rule |
| `DATEDIFF` | Emulated with `age()` or an extension-pack function; boundary semantics vary | `fn_months_between`, `usp_report_claims_ageing`, `usp_rate_renewal` |
| Procedures returning result sets | Converted to functions returning `refcursor` or `SETOF`; callers change | every procedure control |
| Triggers | Converted to `FOR EACH ROW` | `trg_*` multi-row controls |
| `THROW` / error text | Error numbers and text not kept | error-path cases |
| Extension pack (`aws_sqlserver_ext`) | SCT can emit calls to its extension pack schema; this repo avoids that dependency | build fails if `aws_sqlserver_ext` is missing |

## Babelfish

Babelfish for Aurora PostgreSQL accepts the TDS protocol and much of T-SQL, so applications can connect with little change. This lab targets native PostgreSQL instead, so the estate stops depending on T-SQL semantics. Babelfish is listed as an alternative only.
