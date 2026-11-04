# SQL Server → PostgreSQL migration map

Every object in `source/sqlserver/`, its PostgreSQL target file and its phase. Phase 1 is converted on `main`. Phase 2 is the live-demo work: on `main` those target files do not exist yet and reconcile reports the object as **NOT CONVERTED**.

Every target object is created in namespace `$(NS)` with the legacy name (schema prefix dropped; `ref.` tables are created in the same namespace). Procedures become PL/pgSQL functions. Raw copies of every table are in `raw.<schema>_<table>`, e.g. `raw.dbo_policy`.

| Source object | Type | Source file | Category | Phase | Target file |
|---|---|---|---|---|---|
| `ref.country` | table | `source/sqlserver/schema/010_ref_country.sql` | table | 1 | `migrations/020_ref_tables.sql` |
| `ref.product` | table | `source/sqlserver/schema/011_ref_product.sql` | table | 1 | `migrations/020_ref_tables.sql` |
| `dbo.broker` | table | `source/sqlserver/schema/020_broker.sql` | table | 1 | `migrations/030_party_tables.sql` |
| `dbo.policyholder` | table | `source/sqlserver/schema/021_policyholder.sql` | table | 1 | `migrations/030_party_tables.sql` |
| `dbo.policy` | table | `source/sqlserver/schema/030_policy.sql` | table | 1 | `migrations/040_policy_tables.sql` |
| `dbo.policy_version` | table | `source/sqlserver/schema/031_policy_version.sql` | table | 1 | `migrations/040_policy_tables.sql` |
| `dbo.coverage` | table | `source/sqlserver/schema/032_coverage.sql` | table | 1 | `migrations/040_policy_tables.sql` |
| `dbo.premium_schedule` | table | `source/sqlserver/schema/040_premium_schedule.sql` | table | 1 | `migrations/050_premium_tables.sql` |
| `dbo.premium_payment` | table | `source/sqlserver/schema/041_premium_payment.sql` | table | 1 | `migrations/050_premium_tables.sql` |
| `dbo.claim` | table | `source/sqlserver/schema/050_claim.sql` | table | 1 | `migrations/060_claim_tables.sql` |
| `dbo.claim_reserve` | table | `source/sqlserver/schema/051_claim_reserve.sql` | table | 1 | `migrations/060_claim_tables.sql` |
| `dbo.claim_payment` | table | `source/sqlserver/schema/052_claim_payment.sql` | table | 1 | `migrations/060_claim_tables.sql` |
| `dbo.audit_log` | table | `source/sqlserver/schema/060_audit_log.sql` | table | 1 | `migrations/070_audit_log.sql` |
| `dbo.seq_policy_number` | sequence | `source/sqlserver/schema/002_sequences.sql` | sequence | 1 | `migrations/010_sequences.sql` |
| `dbo.seq_claim_number` | sequence | `source/sqlserver/schema/002_sequences.sql` | sequence | 1 | `migrations/010_sequences.sql` |
| `dbo.fn_format_name` | function | `source/sqlserver/functions/fn_format_name.sql` | function | 1 | `migrations/100_functions.sql` |
| `dbo.fn_months_between` | function | `source/sqlserver/functions/fn_months_between.sql` | function | 1 | `migrations/100_functions.sql` |
| `dbo.fn_pro_rata` | function | `source/sqlserver/functions/fn_pro_rata.sql` | function | 1 | `migrations/100_functions.sql` |
| `dbo.tvf_policy_coverage_summary` | function | `source/sqlserver/functions/tvf_policy_coverage_summary.sql` | function | 1 | `migrations/100_functions.sql` |
| `dbo.vw_active_policy` | view | `source/sqlserver/views/vw_active_policy.sql` | view | 1 | `migrations/200_views.sql` |
| `dbo.vw_broker_portfolio` | view | `source/sqlserver/views/vw_broker_portfolio.sql` | view | 1 | `migrations/200_views.sql` |
| `dbo.vw_claim_position` | view | `source/sqlserver/views/vw_claim_position.sql` | view | 1 | `migrations/200_views.sql` |
| `dbo.vw_policy_coverage_pivot` | view | `source/sqlserver/views/vw_policy_coverage_pivot.sql` | view | 1 | `migrations/200_views.sql` |
| `dbo.usp_batch_lapse_overdue` | procedure | `source/sqlserver/procedures/batch/usp_batch_lapse_overdue.sql` | batch | 2 | `migrations/710_batch_lapse_overdue.sql` |
| `dbo.usp_batch_mark_overdue` | procedure | `source/sqlserver/procedures/batch/usp_batch_mark_overdue.sql` | batch | 2 | `migrations/700_batch_mark_overdue.sql` |
| `dbo.usp_batch_nightly` | procedure | `source/sqlserver/procedures/batch/usp_batch_nightly.sql` | batch | 2 | `migrations/730_batch_nightly.sql` |
| `dbo.usp_batch_sync_broker_commission` | procedure | `source/sqlserver/procedures/batch/usp_batch_sync_broker_commission.sql` | batch | 2 | `migrations/720_batch_sync_broker_commission.sql` |
| `dbo.usp_claim_close` | procedure | `source/sqlserver/procedures/claims/usp_claim_close.sql` | claims | 2 | `migrations/530_claim_close.sql` |
| `dbo.usp_claim_open` | procedure | `source/sqlserver/procedures/claims/usp_claim_open.sql` | claims | 2 | `migrations/500_claim_open.sql` |
| `dbo.usp_claim_payment_record` | procedure | `source/sqlserver/procedures/claims/usp_claim_payment_record.sql` | claims | 2 | `migrations/520_claim_payment_record.sql` |
| `dbo.usp_claim_reserve_set` | procedure | `source/sqlserver/procedures/claims/usp_claim_reserve_set.sql` | claims | 2 | `migrations/510_claim_reserve_set.sql` |
| `dbo.usp_policy_create` | procedure | `source/sqlserver/procedures/crud/usp_policy_create.sql` | crud | 1 | `migrations/310_crud_policy.sql` |
| `dbo.usp_policy_endorse` | procedure | `source/sqlserver/procedures/crud/usp_policy_endorse.sql` | crud | 1 | `migrations/310_crud_policy.sql` |
| `dbo.usp_policy_get` | procedure | `source/sqlserver/procedures/crud/usp_policy_get.sql` | crud | 1 | `migrations/310_crud_policy.sql` |
| `dbo.usp_policyholder_create` | procedure | `source/sqlserver/procedures/crud/usp_policyholder_create.sql` | crud | 1 | `migrations/300_crud_policyholder.sql` |
| `dbo.usp_policyholder_get` | procedure | `source/sqlserver/procedures/crud/usp_policyholder_get.sql` | crud | 1 | `migrations/300_crud_policyholder.sql` |
| `dbo.usp_premium_payment_record` | procedure | `source/sqlserver/procedures/crud/usp_premium_payment_record.sql` | crud | 1 | `migrations/320_crud_premium_payment.sql` |
| `dbo.usp_premium_schedule_build` | procedure | `source/sqlserver/procedures/rating/usp_premium_schedule_build.sql` | rating | 2 | `migrations/410_premium_schedule_build.sql` |
| `dbo.usp_rate_quote` | procedure | `source/sqlserver/procedures/rating/usp_rate_quote.sql` | rating | 2 | `migrations/400_rate_quote.sql` |
| `dbo.usp_rate_renewal` | procedure | `source/sqlserver/procedures/rating/usp_rate_renewal.sql` | rating | 2 | `migrations/420_rate_renewal.sql` |
| `dbo.usp_report_broker_production` | procedure | `source/sqlserver/procedures/reporting/usp_report_broker_production.sql` | reporting | 2 | `migrations/620_report_broker_production.sql` |
| `dbo.usp_report_claims_ageing` | procedure | `source/sqlserver/procedures/reporting/usp_report_claims_ageing.sql` | reporting | 2 | `migrations/610_report_claims_ageing.sql` |
| `dbo.usp_report_loss_ratio` | procedure | `source/sqlserver/procedures/reporting/usp_report_loss_ratio.sql` | reporting | 2 | `migrations/600_report_loss_ratio.sql` |
| `dbo.usp_report_policy_json` | procedure | `source/sqlserver/procedures/reporting/usp_report_policy_json.sql` | reporting | 2 | `migrations/630_report_policy_json.sql` |
| `dbo.trg_claim_payment_audit` | trigger | `source/sqlserver/triggers/trg_claim_payment_audit.sql` | trigger | 2 | `migrations/950_audit_triggers.sql` |
| `dbo.trg_claim_status_audit` | trigger | `source/sqlserver/triggers/trg_claim_status_audit.sql` | trigger | 2 | `migrations/950_audit_triggers.sql` |
| `dbo.trg_policy_status_audit` | trigger | `source/sqlserver/triggers/trg_policy_status_audit.sql` | trigger | 2 | `migrations/950_audit_triggers.sql` |

Indexes (32 including primary keys and unique constraints) are converted with their tables in Phase 1; the clustered index `cx_policy_version_latest` becomes a plain B-tree index and filtered indexes become partial indexes.

Supporting target-only objects: `001_extensions.sql` (`citext`, `pgcrypto`), `090_identity_reset.sql` (`reset_identities()`, moves identities and sequences past loaded ids), `900_load_from_raw.sql` (loads `raw` into the namespace). Triggers are in `95x`, after the load, the same order as a DMS full load followed by enabling triggers.

## Totals

| Type | Phase 1 | Phase 2 | Total |
|---|---|---|---|
| table | 13 | 0 | 13 |
| sequence | 2 | 0 | 2 |
| function | 4 | 0 | 4 |
| view | 4 | 0 | 4 |
| procedure | 6 | 15 | 21 |
| trigger | 0 | 3 | 3 |
