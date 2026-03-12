# Dbt POC

A **Modern Data Stack** proof-of-concept demonstrating production-grade ELT with data governance using:

- **Airbyte** v0.50.5 — Data extraction & loading (EL)
- **dbt Core** v1.9.0 — Data transformation, contracts, versioning, and testing (T)
- **Airflow** v2.8.1 — Pipeline orchestration
- **Metabase** — Data visualization & BI dashboards (V)
- **PostgreSQL** 15 — Data warehouse (external container)

> **Goal**: Ingest fake e-commerce data (users, products, purchases), transform it through staging → marts → gold layers, produce analytics-ready tables, and visualize them in Metabase dashboards — with enforced data contracts, model versioning, full lineage tracking, and unit-tested business logic.

### What This Demonstrates

- **Complete Modern Data Stack** using only open-source tools — no vendor lock-in, no license fees
- **End-to-end visibility**: raw JSON → typed views → business dimensions → analytics tables → Metabase dashboards
- **Data contracts** — enforced column names, types, and precision on every materialized table
- **Model versioning** — all governed models stamped at v1, enabling safe schema evolution
- **Full lineage** — from raw sources through transformations to declared downstream consumers (dashboards, reports, ML pipelines)
- **54 automated quality checks** — 44 data tests + 4 unit tests + 6 contract enforcement checks
- **Interleaved execution** — `dbt build` runs models and tests in dependency order; a failing test blocks downstream propagation
- **Two setup modes**: live Airbyte ingestion or instant seed data for fast evaluation

---

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Key Design Decisions](#key-design-decisions)
- [ELT Pipeline Explained](#elt-pipeline-explained)
- [Data Governance](#data-governance)
- [Setup Guide](#setup-guide)
- [Running the Pipeline](#running-the-pipeline)
- [Query Examples](#query-examples)
- [Visualizing Results](#visualizing-results)
- [Data Quality](#data-quality)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Extending to Production](#extending-to-production)
- [Roadmap](#roadmap)
- [Resources](#resources)

---

## Quick Start

```bash
# 1. Clone and setup (auto-creates network, PostgreSQL container, and .env)
git clone <repo-url> && cd dbt-airbyte
./scripts/setup.sh --seed

# 2. Run the ELT pipeline
./scripts/run_pipeline.sh

# 3. Query the results
docker exec -it postgres psql -U postgres -d airbyte_raw \
  -c "SELECT full_name, total_spent, avg_purchase_value FROM gold.gold_user_purchases_v1;"
```

### Setup Modes

```bash
# Full setup WITH Airbyte (live ELT pipeline)
./scripts/setup.sh

# Lightweight setup WITHOUT Airbyte (uses seed data, faster)
./scripts/setup.sh --seed

# Infrastructure only — no Airbyte, no seed data (bring your own data)
./scripts/setup.sh --no-airbyte

# Cleanup everything
./scripts/setup.sh --clean
```

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | 20.10+ | With Docker Compose v2 |
| PostgreSQL Container | 15+ | External container on port 5432 (auto-created by `setup.sh` if absent) |
| Docker Socket | — | Airflow uses `docker exec` to run dbt and seed commands. The Docker socket must be accessible (mounted automatically by docker-compose). |

### Component Versions

| Component | Version | Image / Package |
|-----------|---------|-----------------|
| dbt Core | 1.9.0 | `ghcr.io/dbt-labs/dbt-postgres:1.9.0` |
| Airflow | 2.8.1 | `apache/airflow:2.8.1-python3.11` |
| Airbyte OSS | 0.50.5 | `docker-compose.airbyte.yaml` (8 services) |
| Metabase | latest | `metabase/metabase:latest` |
| PostgreSQL | 15 | `postgres:15` (external container) |
| Python (Airflow) | 3.11 | Bundled in Airflow image |

### Verify Prerequisites

```bash
# Check Docker
docker --version

# Check network exists (or let setup.sh create it)
docker network ls | grep poc-network

# Check PostgreSQL is running
docker ps | grep postgres
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                 poc-network                                       │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐        │
│  │   Airbyte    │  │   Airflow    │  │  dbt-runner  │  │   Metabase    │        │
│  │   :8000      │  │   :8080      │  │  docs :52419 │  │   :54892      │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘        │
│         │                 │                 │                   │               │
│         │    ┌────────────┴─────────────────┘                   │               │
│         │    │                                                  │               │
│         ▼    ▼                                                  ▼               │
│  ┌────────────────────────────────────────────────────────────────────────┐      │
│  │                        PostgreSQL :5432                                │      │
│  │  ┌─────────────────┐        ┌────────────────────────────┐            │      │
│  │  │   airbyte_raw   │        │       dbt transforms       │◀── queries │      │
│  │  │  (raw JSON)     │───────▶│  staging → marts → gold    │            │      │
│  │  └─────────────────┘        └────────────────────────────┘            │      │
│  └────────────────────────────────────────────────────────────────────────┘      │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airbyte** | http://localhost:8000 | `airbyte` / `password` |
| **Airflow** | http://localhost:8080 | `admin` / `admin` |
| **Metabase** | http://localhost:54892 | Setup wizard on first launch |
| **dbt Docs** | http://localhost:52419 | — (auto-started by `setup.sh`) |
| **PostgreSQL** | localhost:5432 | See `.env` |

### Databases & Users

| Database | User | Purpose |
|----------|------|---------|
| `airbyte_raw` | `airbyte_user` | Raw data from Airbyte + dbt transforms (staging, marts, gold) |

### Configuration

The project uses a two-file environment chain:

| File | Purpose | Managed by |
|------|---------|------------|
| `.env` | User config — `POSTGRES_CONTAINER`, `POSTGRES_USER`, `DOCKER_NETWORK` | You (copied from `.env.example` on first run) |
| `.env.generated` | Auto-generated credentials and derived variables | `setup.sh` (regenerated on each run, do not edit) |

Both files are loaded by `docker-compose.yaml` via `env_file:`. Containers see the merged result.

**Default credentials** (POC constants defined in `setup.sh`, not secrets):

| Service | User | Password |
|---------|------|----------|
| dbt | `dbt_user` | `dbt_password` |
| Airbyte DB | `airbyte_user` | `airbyte_password` |
| Airbyte Web | `airbyte` | `password` |
| Airflow | `admin` | `admin` |

To customize, edit the `GEN_*` variables at the top of `scripts/setup.sh` before running setup.

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Views for staging, tables for marts/gold | Staging is pass-through (cheap to rebuild); marts/gold are aggregated (expensive to recompute) |
| Single database, multiple schemas | Simpler Docker setup; schemas provide logical separation without cross-DB permission complexity |
| full_refresh + overwrite | Stateless and idempotent — correct for a POC. Incremental adds complexity without adding demo value |
| Faker seed=42 | Deterministic data — same results every run, reproducible demos |
| Airflow `docker exec` pattern | Avoids embedding dbt inside Airflow image; keeps containers single-purpose |
| `dbt build` (interleaved execution) | Models and tests run in dependency order — a failing staging test blocks marts from building. Replaces separate run/test tasks. |
| Enforced contracts on marts/gold | Column names, types, and precision are declared in YAML. A schema mismatch fails the build before bad data lands. |
| Versioned models (v1) | All governed models are stamped v1. Future breaking changes increment the version; downstream consumers pin or migrate explicitly. |
| `numeric(12,2)` for USD amounts | Explicit precision prevents silent rounding. Contracts enforce this at the DDL level. |
| Exposures for lineage | Downstream consumers (dashboards, reports, ML) are declared in YAML. `dbt docs` shows the full impact graph. |

---

## ELT Pipeline Explained

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ELT Pipeline Flow                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  EXTRACT & LOAD (Airbyte)              TRANSFORM (dbt)                      │
│  ─────────────────────────             ───────────────                      │
│                                                                             │
│  ┌─────────────┐                                                            │
│  │ Faker Source│──┐                                                         │
│  │  (users)    │  │     ┌─────────────┐    ┌──────────────┐                │
│  └─────────────┘  │     │   STAGING   │    │    MARTS     │                │
│  ┌─────────────┐  │     │   (views)   │    │   (tables)   │   ┌─────────┐  │
│  │ Faker Source│──┼────▶│             │───▶│              │──▶│  GOLD   │  │
│  │ (products)  │  │     │ • stg_users │    │ • dim_users  │   │(tables) │  │
│  └─────────────┘  │     │ • stg_prods │    │ • dim_prods  │   │         │  │
│  ┌─────────────┐  │     │ • stg_purch │    │              │   │ • gold_ │  │
│  │ Faker Source│──┘     └─────────────┘    └──────────────┘   │  user_  │  │
│  │ (purchases) │                                              │  purch  │  │
│  └─────────────┘                                              └─────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Sync Mode

Airbyte connections use **full_refresh + overwrite** — each sync replaces all destination data. This is intentional for a POC (simple, stateless, idempotent). Production pipelines would use incremental sync with deduplication.

### Layer Descriptions

| Layer | Schema | Type | Purpose |
|-------|--------|------|---------|
| **Raw** | `public` | Tables | Raw JSON from Airbyte (`_airbyte_raw_*`) |
| **Staging** | `staging` | Views | Cleaned, typed, extracted from JSON |
| **Marts** | `marts` | Tables | Business dimensions with aggregations |
| **Gold** | `gold` | Tables | Analytics-ready for BI tools |

### What Each Layer Does

#### Raw Layer (Airbyte)
```sql
-- Raw JSON blobs as ingested by Airbyte
SELECT _airbyte_data FROM _airbyte_raw_users LIMIT 1;
-- {"id": 1, "name": "Alice Johnson", "email": "alice@...", "address": {...}}
```

#### Staging Layer (dbt views)
```sql
-- Extracts and types fields from JSON
SELECT user_id, full_name, email, occupation, city, age
FROM staging.stg_users;
```

#### Marts Layer (dbt tables — contracted, versioned)
```sql
-- Dimension tables with enforced contracts and explicit precision
SELECT user_id, full_name, total_purchases, total_spent, first_purchase_at
FROM marts.dim_users_v1_v1;

SELECT product_id, make, model, year, price
FROM marts.dim_products_v1_v1;
```

#### Gold Layer (dbt tables — contracted, versioned, unit-tested)
```sql
-- Final analytics-ready table with unit-tested business logic
SELECT full_name, total_spent, avg_purchase_value, return_rate_pct, last_purchased_product
FROM gold.gold_user_purchases_v1_v1;
```

---

## Data Governance

This POC implements dbt's full governance stack: **data contracts**, **model versioning**, **unit tests**, and **lineage tracking via exposures**. These features work together to make schema changes safe, business logic verifiable, and downstream impact visible.

### Data Contracts

Every materialized model (marts and gold) has an **enforced contract** — a YAML declaration of every column's name, type, and precision. If the SQL output doesn't match the contract, `dbt build` fails before any data lands.

```yaml
# models/gold/schema.yml (excerpt)
models:
  - name: gold_user_purchases
    config:
      contract:
        enforced: true
    columns:
      - name: total_spent
        data_type: numeric(12,2)    # Explicit precision — no silent rounding
      - name: return_rate_pct
        data_type: numeric(5,1)     # Percentage: 0.0 – 100.0
      - name: user_created_at
        data_type: timestamptz      # Timezone-aware, matches source
```

**What contracts enforce:**

| Violation | What happens |
|-----------|-------------|
| Column renamed in SQL but not in contract | Build fails — contract mismatch |
| Column added to SQL without contract entry | Build fails — unexpected column |
| Column removed from SQL but still in contract | Build fails — missing column |
| Type changed (e.g., `integer` → `text`) | Build fails — type mismatch |
| Precision exceeded (e.g., value too large for `numeric(5,1)`) | PostgreSQL raises overflow error |

**Contracted models:**

| Model | Schema | Columns | Precision-typed |
|-------|--------|---------|-----------------|
| `dim_users_v1` | `marts` | 14 | `total_spent numeric(12,2)`, `age integer`, all timestamps `timestamptz` |
| `dim_products_v1` | `marts` | 9 | `price numeric(12,2)`, `year integer`, all timestamps `timestamptz` |
| `gold_user_purchases_v1` | `gold` | 18 | `total_spent`, `avg_purchase_value`, `last_purchased_price` as `numeric(12,2)`; `return_rate_pct` as `numeric(5,1)` |

### Model Versioning

All governed models are stamped at **v1**, enabling safe schema evolution. When a breaking change is needed (column rename, type change, column removal), a new version is created — downstream consumers choose when to migrate.

```yaml
# models/marts/schema.yml (excerpt)
models:
  - name: dim_users
    latest_version: 1
    versions:
      - v: 1
        defined_in: dim_users   # SQL file keeps its original name
```

**How versioning works in practice:**

| Scenario | Without versioning | With versioning |
|----------|-------------------|-----------------|
| Rename `total_spent` → `lifetime_revenue` | Downstream breaks silently | Create v2 with new name; v1 stays live until consumers migrate |
| Add required column | Downstream may break on SELECT * | New version; old version unaffected |
| Change `numeric` → `integer` | Silent precision loss | Contract on v2 enforces new type; v1 retains old type |

**Database impact:** Versioned models materialize with a `_v1` suffix (e.g., `marts.dim_users_v1`). The `ref('dim_users')` function resolves to the latest version automatically — no SQL changes needed in downstream models.

### Unit Tests

Four unit tests validate the business logic in `gold_user_purchases` using **known inputs and expected outputs** — no database required. These run as part of `dbt build` and block model materialization if they fail.

```yaml
# models/gold/unit_tests.yml (excerpt)
unit_tests:
  - name: test_return_rate_calculation
    model: gold_user_purchases.v1
    given:
      - input: ref('dim_users')
        rows:
          - {user_id: 1, total_purchases: 10, total_returns: 3, ...}
    expect:
      rows:
        - {user_id: 1, return_rate_pct: 30.0}
```

| Unit Test | What It Proves |
|-----------|---------------|
| `test_return_rate_calculation` | `return_rate_pct = total_returns / total_purchases * 100`, rounded to 1 decimal |
| `test_avg_purchase_value` | `avg_purchase_value = total_spent / total_purchases`, rounded to 2 decimals |
| `test_user_with_no_returns` | `return_rate_pct = 0.0` when `total_returns = 0` (no division error) |
| `test_last_purchased_product` | Most recent purchase is selected; formatted as `"Make Model"` |

**Execution order:** Unit tests run *before* model materialization. If the return rate formula is wrong, the gold table is never built — bad logic never reaches the database.

### Lineage & Exposures

Three **exposures** declare downstream consumers of the dbt models. These appear in the `dbt docs` lineage graph, making impact analysis visible without tribal knowledge.

```yaml
# models/exposures.yml
exposures:
  - name: executive_kpi_dashboard
    type: dashboard
    depends_on:
      - ref('gold_user_purchases', v=1)

  - name: product_performance_report
    type: analysis
    depends_on:
      - ref('dim_products', v=1)
      - ref('gold_user_purchases', v=1)

  - name: customer_segmentation_model
    type: ml
    depends_on:
      - ref('gold_user_purchases', v=1)
      - ref('dim_users', v=1)
```

**Full lineage path:**

```
Sources (Airbyte raw)
  └─→ Staging views (stg_users, stg_products, stg_purchases)
        └─→ Mart tables (dim_users_v1, dim_products_v1)  [contracted]
              └─→ Gold table (gold_user_purchases_v1)     [contracted + unit-tested]
                    └─→ Exposures:
                          ├─ Executive KPI Dashboard
                          ├─ Product Performance Report
                          └─ Customer Segmentation ML Pipeline
```

**View the lineage graph:**
```bash
docker exec dbt-runner dbt docs generate
docker exec -d dbt-runner dbt docs serve --port 52419
# Open http://localhost:52419 → click any model → view lineage
```

### How It All Fits Together

When `dbt build` runs, these governance features execute in order:

```
1. Source tests       → Raw data has content
2. Staging views      → JSON extracted and typed
3. Staging tests      → Structural integrity (not null, unique, FK)
4. Mart contracts     → Column names, types, precision match declaration  ← NEW
5. Mart tables        → dim_users_v1, dim_products_v1 materialized
6. Mart tests         → Data quality on dimensions
7. Gold unit tests    → Business logic verified with known I/O            ← NEW
8. Gold contract      → Schema matches declaration                        ← NEW
9. Gold table         → gold_user_purchases_v1 materialized
10. Gold tests        → Final data quality checks
```

A failure at **any** step blocks everything downstream. Bad data never propagates.

---

## Setup Guide

### Step 1: Run Setup Script

```bash
./scripts/setup.sh
```

This automatically:
- ✅ Creates databases (`airbyte_raw`, `metabase`) and users
- ✅ Creates dbt schemas (staging, marts, gold)
- ✅ Starts Airbyte (full mode) or seeds test data (`--seed` mode)
- ✅ Starts Airflow + dbt-runner + Metabase
- ✅ Configures Airbyte source, destination, and connection (full mode)
- ✅ Sets Airflow variable `airbyte_connection_id` (full mode)
- ✅ Runs `dbt build` and starts dbt docs server (`--seed` mode)

### Step 2: Verify Services

```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "airbyte|airflow|dbt"
```

### Step 3: Access UIs

- **Airbyte**: http://localhost:8000 → Verify connection is created
- **Airflow**: http://localhost:8080 → Check `elt_pipeline` DAG exists
- **Metabase**: http://localhost:54892 → Complete setup wizard (auto-started, connects to `gold` schema)
- **dbt Docs**: http://localhost:52419 → Browse model lineage and documentation (`--seed` mode)

---

## Running the Pipeline

### Option 1: Using the Runner Script (Recommended)

```bash
./scripts/run_pipeline.sh
```

This triggers the Airflow DAG and monitors progress in real-time:

```
┌──────────────────────────┬───────────────────────┬──────────────────────────────────┐
│ Task                     │ State                 │ Duration                         │
├──────────────────────────┼───────────────────────┼──────────────────────────────────┤
│ check_data_source_mode   │ ✓ success             │ 0s                               │
│ trigger_airbyte_sync     │ ✓ success             │ 45s                              │
│ seed_raw_data            │ ○ skipped             │ -                                │
│ data_loaded              │ ✓ success             │ 0s                               │
│ dbt_build                │ ✓ success             │ ~2s (54 checks)                  │
│ pipeline_complete        │ ✓ success             │ 0s                               │
└──────────────────────────┴───────────────────────┴──────────────────────────────────┘
```

### Option 2: Using Airflow UI

1. Open http://localhost:8080
2. Find `elt_pipeline` DAG
3. Click **Trigger DAG** (play button)
4. Monitor in Graph view

### Option 3: Manual dbt Commands

```bash
# Full build — models + tests interleaved in dependency order (recommended)
docker exec dbt-runner dbt build

# Run only unit tests (no database required for logic validation)
docker exec dbt-runner dbt test --select test_type:unit

# Run only data tests
docker exec dbt-runner dbt test --select test_type:data

# Run specific layer
docker exec dbt-runner dbt build --select staging
docker exec dbt-runner dbt build --select marts
docker exec dbt-runner dbt build --select gold

# Run tests for a specific model
docker exec dbt-runner dbt test --select dim_users
```

### Pipeline Tasks Explained

| Task | Description | Duration |
|------|-------------|----------|
| `check_data_source_mode` | Decides: Airbyte sync or seed data | <1s |
| `trigger_airbyte_sync` | Calls Airbyte API, waits for sync completion | 30-60s |
| `seed_raw_data` | Loads test SQL (only if Airbyte not configured) | <1s |
| `data_loaded` | Join point — waits for whichever data source completed | <1s |
| `dbt_build` | Builds all models + runs all tests in dependency order (54 checks: 3 source tests, 20 staging tests, 14 mart tests, 4 unit tests, 3 contract checks, 10 gold tests) | ~2s |
| `pipeline_complete` | Logs completion summary | <1s |

---

## Query Examples

### Connect to Database

```bash
docker exec -it postgres psql -U postgres -d airbyte_raw
```

### Gold Layer Queries

#### Top Spenders
```sql
SELECT full_name, total_spent, total_purchases, avg_purchase_value
FROM gold.gold_user_purchases_v1
ORDER BY total_spent DESC
LIMIT 10;
```

#### High Return Rate Customers
```sql
SELECT full_name, return_rate_pct, total_returns, total_purchases
FROM gold.gold_user_purchases_v1
WHERE return_rate_pct > 50
ORDER BY return_rate_pct DESC;
```

#### Customer Lifetime Value
```sql
SELECT
    full_name,
    total_spent,
    avg_purchase_value,
    total_purchases,
    last_purchase_at - first_purchase_at as customer_tenure
FROM gold.gold_user_purchases_v1
ORDER BY total_spent DESC;
```

#### Recent Purchasers
```sql
SELECT full_name, last_purchased_product, last_purchased_price, last_purchase_at
FROM gold.gold_user_purchases_v1
WHERE last_purchase_at > NOW() - INTERVAL '30 days'
ORDER BY last_purchase_at DESC;
```

#### Geographic Analysis
```sql
SELECT city, state, country_code, COUNT(*) as customers, SUM(total_spent) as revenue
FROM gold.gold_user_purchases_v1
GROUP BY city, state, country_code
ORDER BY revenue DESC;
```

---

## Visualizing Results

### Metabase Dashboards

Metabase provides interactive dashboards on top of the gold layer. It starts automatically with `setup.sh` — no manual Docker commands needed.

> **One-time setup wizard**: On first launch, Metabase requires a setup wizard (create admin account, add database). This cannot be automated — Metabase has no headless config API for initial setup. Subsequent launches skip the wizard entirely.

Open http://localhost:54892 and complete the wizard. When you reach **Step 3: Add your data**, click **PostgreSQL** and fill in:

| Field | Value |
|-------|-------|
| Display name | `ELT Pipeline (Gold)` (or any name you prefer) |
| Host | `postgres` |
| Port | `5432` |
| Database name | `airbyte_raw` |
| Username | `dbt_user` |
| Password | `dbt_password` |
| Schemas | `All` (or select `gold` + `marts` to scope it) |
| SSL | Off |
| SSH tunnel | Off |

**Dashboard ideas from `gold_user_purchases`:**

- Top spenders by `total_spent` (bar chart)
- Return rate distribution (histogram of `return_rate_pct`)
- Revenue by `country_code` (pie chart)
- Avg purchase value vs return rate (scatter plot)
- Purchase activity timeline (line chart using `first_purchase_at` / `last_purchase_at`)

### Quick Data Showcase

```bash
# Row counts across all layers
echo "=== RAW LAYER ===" && \
docker exec postgres psql -U postgres -d airbyte_raw -c \
  "SELECT '_airbyte_raw_users' as table_name, COUNT(*) FROM _airbyte_raw_users
   UNION ALL SELECT '_airbyte_raw_products', COUNT(*) FROM _airbyte_raw_products
   UNION ALL SELECT '_airbyte_raw_purchases', COUNT(*) FROM _airbyte_raw_purchases;"

echo "=== STAGING LAYER ===" && \
docker exec postgres psql -U postgres -d airbyte_raw -c \
  "SELECT user_id, full_name, occupation, city FROM staging.stg_users LIMIT 5;"

echo "=== MARTS LAYER ===" && \
docker exec postgres psql -U postgres -d airbyte_raw -c \
  "SELECT user_id, full_name, total_purchases, total_spent FROM marts.dim_users_v1 LIMIT 10;"

echo "=== GOLD LAYER ===" && \
docker exec postgres psql -U postgres -d airbyte_raw -c \
  "SELECT full_name, total_spent, avg_purchase_value, return_rate_pct FROM gold.gold_user_purchases_v1 LIMIT 10;"
```

### dbt Documentation

In `--seed` mode, dbt docs are automatically generated and served by `setup.sh` at http://localhost:52419 (after `dbt build` completes). To regenerate manually after model changes:

```bash
docker exec dbt-runner dbt docs generate
docker exec -d dbt-runner dbt docs serve --port 52419

# Open in browser
open http://localhost:52419
```

---

## Data Quality

### Test Summary

The project runs **54 automated checks** on every `dbt build`, covering structural integrity, referential consistency, business logic correctness, and schema compliance.

| Check Type | Count | What It Catches |
|------------|-------|-----------------|
| **Data tests** (`not_null`, `unique`, `relationships`) | 44 | Missing values, duplicate keys, broken foreign keys |
| **Unit tests** (known-input/expected-output) | 4 | Wrong business logic (formulas, calculations, edge cases) |
| **Contract enforcement** (column name + type + precision) | 6 | Schema drift, type mismatches, unexpected columns |
| | **54** | |

### Test Coverage by Layer

| Layer | Model | Data Tests | Unit Tests | Contract | Total |
|-------|-------|-----------|-----------|----------|-------|
| **Sources** | `_airbyte_raw_*` (3 tables) | 3 | — | — | 3 |
| **Staging** | `stg_users` | 4 | — | — | 4 |
| **Staging** | `stg_products` | 4 | — | — | 4 |
| **Staging** | `stg_purchases` | 5 | — | — | 5 |
| **Marts** | `dim_users_v1` | 6 | — | 14 cols | 6 + contract |
| **Marts** | `dim_products_v1` | 5 | — | 9 cols | 5 + contract |
| **Gold** | `gold_user_purchases_v1` | 7 | 4 | 18 cols | 11 + contract |

### Running Tests

```bash
# Full build — models + all tests interleaved (recommended)
docker exec dbt-runner dbt build

# Unit tests only (validates business logic without touching the database)
docker exec dbt-runner dbt test --select test_type:unit

# Data tests only (validates data properties)
docker exec dbt-runner dbt test --select test_type:data

# Tests for a specific model
docker exec dbt-runner dbt test --select gold_user_purchases
```

### Seed Data (--seed mode)

When running with `./scripts/setup.sh --seed`, the pipeline uses deterministic test data:

| Entity | Count | Details |
|--------|-------|---------|
| Users | 12 | Across 6 countries (US, UK, DE, JP, BR, AU), varied ages and occupations |
| Products | 8 | Cars with varied price tiers ($22K–$85K), multiple manufacturers |
| Purchases | 35 | Mix of active buyers and returners, varied spending patterns |

All 12 users have at least one purchase, so every user appears in the gold output. UUIDs are generated with `gen_random_uuid()` (PostgreSQL `pgcrypto` extension, auto-created).

---

## Troubleshooting

### Airbyte Connection Failed

**Error:** `State code: 08001; Message: The connection attempt failed`

**Cause:** Airbyte connectors run with `--network host`, so Docker DNS (`postgres`) doesn't work.

**Fix:** Use `localhost` as the host in Airbyte destination settings, not `postgres`.

---

### `trigger_airbyte_sync` is Skipped

**Cause:** Airflow variable `airbyte_connection_id` is not set.

**Fix:**
```bash
# Get connection ID from Airbyte
curl -s -X POST "http://localhost:8000/api/v1/connections/list" \
  -u "airbyte:password" -H "Content-Type: application/json" \
  -d '{}' | python3 -c "import sys,json; print(json.load(sys.stdin)['connections'][0]['connectionId'])"

# Set in Airflow
docker exec airflow airflow variables set airbyte_connection_id "<connection-id>"
```

---

### dbt Models Not Found

**Error:** `relation "staging.stg_users" does not exist`

**Cause:** Not connected to correct database.

**Fix:** Connect to `airbyte_raw`:
```bash
docker exec -it postgres psql -U postgres -d airbyte_raw
```

---

### Permission Denied

**Error:** `permission denied for schema staging`

**Fix:** Re-run setup to recreate grants:
```bash
./scripts/setup.sh
```

---

### Airflow DAG Not Visible

**Cause:** DAG file syntax error or not parsed yet.

**Fix:**
```bash
# Check for errors
docker exec airflow airflow dags list

# Force re-parse
docker exec airflow airflow dags reserialize
```

---

## Project Structure

```
dbt-airbyte/
├── docker-compose.yaml          # dbt + Airflow + Metabase containers
├── docker-compose.airbyte.yaml  # Airbyte containers (7 services)
├── .env.example                 # Environment template (auto-copied to .env)
├── airflow/
│   └── dags/
│       └── elt_pipeline.py      # Orchestration DAG
├── dbt_project/
│   ├── dbt_project.yml          # dbt configuration
│   ├── macros/
│   │   └── generate_schema_name.sql  # Custom schema naming (bare names)
│   └── models/
│       ├── sources.yml          # Source definitions (Airbyte raw tables)
│       ├── exposures.yml        # Downstream consumers (dashboards, reports, ML)
│       ├── staging/             # stg_users, stg_products, stg_purchases (+ schema.yml)
│       ├── marts/               # dim_users, dim_products (+ schema.yml with contracts & versions)
│       └── gold/                # gold_user_purchases (+ schema.yml, unit_tests.yml)
├── profiles/
│   └── profiles.yml             # dbt connection profile
├── scripts/
│   ├── setup.sh                 # One-click setup (--seed or full Airbyte)
│   ├── run_pipeline.sh          # Pipeline runner with monitoring
│   ├── configure_airbyte.py     # Airbyte auto-configuration
│   └── seed_test_data.sql       # Sample data for --seed mode
├── docs/
│   └── ROADMAP.md               # CI & quality maturity roadmap
└── README.md
```

---

## Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **PostgreSQL-specific SQL** | Gold model uses `DISTINCT ON` (Postgres-only syntax). Cannot port directly to Snowflake/BigQuery/Redshift. | Rewrite with `ROW_NUMBER()` window function for warehouse portability. |
| **Airbyte version lock** | Connector definition IDs in `configure_airbyte.py` are hardcoded for Airbyte OSS v0.50.5. Different versions use different UUIDs. | Re-inspect via `/api/v1/*Definitions/list` after upgrading Airbyte. |
| **No `description` in `dbt_project.yml`** | dbt 1.9 rejects project-level `description` field (`Additional properties are not allowed`). Supported in dbt 1.10+. | Descriptions live in individual `schema.yml` files instead. |
| **No Docker images past dbt 1.9** | `ghcr.io/dbt-labs/dbt-postgres` registry tops out at `1.9.0`. Upgrading to 1.10+ requires a custom Dockerfile. | Build from `python:3.12-slim` + `pip install dbt-core dbt-postgres`. |
| **Hardcoded credentials** | POC uses plaintext credentials (`dbt_password`, `airbyte_password`). Not suitable for production. | Use a secrets manager (Vault, AWS Secrets Manager). |
| **full_refresh only** | Every sync replaces all data. Acceptable for demo-scale; unsustainable for large datasets. | Switch to incremental + dedup sync mode. |

---

## Extending to Production

This POC already implements several production-grade patterns (contracts, versioning, unit tests, lineage). What remains for a full production deployment:

- **Incremental syncs** — switch from full_refresh to incremental + dedup for large datasets
- **Secrets management** — replace hardcoded POC credentials with a vault (e.g., HashiCorp Vault, AWS Secrets Manager)
- **CI/CD** — add dbt slim CI (`dbt build --select state:modified+`) and Airflow DAG validation (see [roadmap](docs/ROADMAP.md))
- **Monitoring** — add dbt source freshness checks and Elementary observability dashboard (see [roadmap](docs/ROADMAP.md))
- **Scaling** — swap PostgreSQL for a cloud warehouse (Snowflake, BigQuery, Redshift); Airbyte Cloud for managed connectors
- **Multi-team governance** — add dbt groups and access control for team ownership boundaries

---

## Roadmap

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full implementation roadmap.

**Completed:**
- `dbt build` interleaved execution
- Unit tests (4 tests on gold model business logic)
- Model contracts with explicit numeric precision
- Model versioning (all governed models at v1)
- Exposures (3 downstream consumers declared)
- Metabase BI dashboards (gold layer visualization)

**Next up:**
- **Source freshness** — verify raw data recency before transforms (Airbyte mode)
- **Elementary** — dbt-native observability dashboard with test history and anomaly detection
- **SQLFluff** — SQL linting + pre-commit hooks for team code quality
- **GitHub Actions** — slim CI with `dbt build --select state:modified+`
- **Groups & access** — team ownership boundaries with cross-group `ref()` control

---

## Resources

- [Airbyte Documentation](https://docs.airbyte.com/)
- [Airbyte Faker Connector](https://docs.airbyte.com/integrations/sources/faker)
- [dbt Documentation](https://docs.getdbt.com/)
- [Airflow Documentation](https://airflow.apache.org/docs/)

---

## License

MIT License - See [LICENSE](LICENSE) for details.
