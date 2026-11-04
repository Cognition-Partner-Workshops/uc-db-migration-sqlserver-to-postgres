# SQL Server 2022 Express -> PostgreSQL 18 (Aurora PostgreSQL-compatible) migration lab.
#
# NS isolates every build in its own PostgreSQL schema, so parallel demo runs,
# branches and the naive conversion never collide. Default: dev.

NS        ?= dev
RUN_DATE  ?= 2026-11-01
PYTHON    ?= python3
SHELL     := /bin/bash
COMMIT    ?=

.PHONY: help install docker-up docker-down seed build reconcile functional reconcile-naive batch \
        coverage demo-up demo-down lint ci tf-validate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## Install Python dependencies and the pre-commit hooks
	$(PYTHON) -m pip install -r requirements.txt
	pre-commit install

docker-up: ## Start SQL Server 2022 Express and PostgreSQL 18 locally
	docker compose up -d --wait

docker-down: ## Stop the local engines and delete their volumes
	docker compose down -v

seed: ## Deploy the legacy estate, load synthetic data, copy it to PostgreSQL `raw`
	$(PYTHON) seed/deploy_source.py
	$(PYTHON) seed/generate_and_load.py
	$(PYTHON) seed/create_reader_login.py
	$(PYTHON) seed/load_raw.py

build: ## Build PostgreSQL namespace NS from migrations/ and load it from raw
	$(PYTHON) seed/deploy.py --ns $(NS)

reconcile: ## Reconcile SQL Server vs namespace NS -> work/reconcile/report.md
	$(PYTHON) verify/reconcile.py --ns $(NS)

functional: ## Business scenario on both engines, compare resulting state
	$(PYTHON) verify/functional_tests.py --ns $(NS)

reconcile-naive: ## Build NS=naive with the planted naive conversion and reconcile it (expected to FAIL)
	$(PYTHON) seed/deploy.py --ns naive --overlay naive_conversion
	$(PYTHON) verify/reconcile.py --ns naive --report work/reconcile/naive.md

batch: ## Run the legacy nightly batch (rolled back unless COMMIT=1); also NS if converted
	$(PYTHON) seed/run_batch.py --run-date $(RUN_DATE) --ns $(NS) $(if $(COMMIT),--commit,)

coverage: ## Check every promised T-SQL construct is present in source/sqlserver
	$(PYTHON) verify/construct_coverage.py

demo-up: seed build reconcile ## seed + build NS + reconcile NS
	@echo "=== demo up: namespace $(NS), report in work/reconcile/report.md ==="

demo-down: ## Drop namespace NS (the legacy estate and raw stay)
	$(PYTHON) seed/deploy.py --ns $(NS) --drop

lint: ## sqlfluff (T-SQL + PostgreSQL), ruff, yamllint
	sqlfluff lint source/ migrations/ naive_conversion/
	ruff check seed verify
	ruff format --check seed verify
	yamllint .

tf-validate: ## terraform validate only (never plan/apply)
	cd infra/terraform && terraform init -backend=false -input=false >/dev/null && terraform validate

ci: lint coverage build reconcile functional ## What CI runs (after docker-up + seed)
