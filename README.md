# Airbyte + dbt POC

A minimalistic **Modern Data Stack** proof-of-concept demonstrating end-to-end ELT (Extract, Load, Transform) using:

- **Airbyte** v0.50.5 — Data extraction & loading (EL)
- **dbt Core** v1.9.0 — Data transformation (T)
- **Airflow** v2.8.1 — Pipeline orchestration
- **PostgreSQL** 15 — Data warehouse (external container)

> 🎯 **Goal**: Ingest fake e-commerce data (users, products, purchases), transform it through staging → marts → gold layers, and produce analytics-ready tables.

### What This Demonstrates

- **Complete Modern Data Stack** using only open-source tools — no vendor lock-in, no license fees
- **Automated ELT pipeline**: raw JSON → typed views → business dimensions → analytics tables
- **Two setup modes**: live Airbyte ingestion or instant seed data for fast evaluation
- **Pipeline orchestration** with Airflow, including branching logic and data quality gates (44 dbt tests)

---

## 📑 Table of Contents

- [Quick Start](#-quick-start)
- [Prerequisites](#-prerequisites)
- [Architecture](#-architecture)
- [Key Design Decisions](#-key-design-decisions)
- [ELT Pipeline Explained](#-elt-pipeline-explained)
- [Setup Guide](#-setup-guide)
- [Running the Pipeline](#-running-the-pipeline)
- [Query Examples](#-query-examples)
- [Visualizing Results](#-visualizing-results)
- [Data Quality](#-data-quality)
- [Troubleshooting](#-troubleshooting)
- [Known Limitations](#-known-limitations)
- [Extending to Production](#-extending-to-production)
- [Roadmap](#-roadmap)
- [Resources](#-resources)

---

## 🚀 Quick Start

```bash
# 1. Clone and setup (auto-creates network, PostgreSQL container, and .env)
git clone <repo-url> && cd dbt-airbyte
./scripts/setup.sh --seed

# 2. Run the ELT pipeline
./scripts/run_pipeline.sh

# 3. Query the results
docker exec -it postgres psql -U postgres -d airbyte_raw \
  -c "SELECT full_name, total_spent, avg_purchase_value FROM gold.gold_user_purchases;"
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

## 📋 Prerequisites

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

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              poc-network                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │   Airbyte    │     │   Airflow    │     │  dbt-runner  │                │
│  │   :8000      │     │   :8080      │     │  (container) │                │
│  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘                │
│         │                    │                    │                        │
│         │    ┌───────────────┴────────────────────┘                        │
│         │    │                                                             │
│         ▼    ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │                   PostgreSQL :5432                          │           │
│  │  ┌─────────────────┐         ┌────────────────────────────┐ │           │
│  │  │   airbyte_raw   │         │       dbt transforms       │ │           │
│  │  │  (raw JSON)     │────────▶│  staging → marts → gold    │ │           │
│  │  └─────────────────┘         └────────────────────────────┘ │           │
│  └─────────────────────────────────────────────────────────────┘           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airbyte** | http://localhost:8000 | `airbyte` / `password` |
| **Airflow** | http://localhost:8080 | `admin` / `admin` |
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

## 🔑 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Views for staging, tables for marts/gold | Staging is pass-through (cheap to rebuild); marts/gold are aggregated (expensive to recompute) |
| Single database, multiple schemas | Simpler Docker setup; schemas provide logical separation without cross-DB permission complexity |
| full_refresh + overwrite | Stateless and idempotent — correct for a POC. Incremental adds complexity without adding demo value |
| Faker seed=42 | Deterministic data — same results every run, reproducible demos |
| Airflow `docker exec` pattern | Avoids embedding dbt inside Airflow image; keeps containers single-purpose |

---

## 🔄 ELT Pipeline Explained

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

#### 📥 Raw Layer (Airbyte)
```sql
-- Raw JSON blobs as ingested by Airbyte
SELECT _airbyte_data FROM _airbyte_raw_users LIMIT 1;
-- {"id": 1, "name": "Alice Johnson", "email": "alice@...", "address": {...}}
```

#### 🔄 Staging Layer (dbt views)
```sql
-- Extracts and types fields from JSON
SELECT user_id, full_name, email, occupation, city, age
FROM staging.stg_users;
```

#### 📊 Marts Layer (dbt tables)
```sql
-- Dimension tables: users with aggregated metrics, products catalog
SELECT user_id, full_name, total_purchases, total_spent, first_purchase_at
FROM marts.dim_users;

SELECT product_id, make, model, year, price
FROM marts.dim_products;
```

#### ⭐ Gold Layer (dbt tables)
```sql
-- Final analytics-ready table with computed metrics
SELECT full_name, total_spent, avg_purchase_value, return_rate_pct, last_purchased_product
FROM gold.gold_user_purchases;
```

---

## 🔧 Setup Guide

### Step 1: Run Setup Script

```bash
./scripts/setup.sh
```

This automatically:
- ✅ Creates database (`airbyte_raw`) and users
- ✅ Creates dbt schemas (staging, marts, gold)
- ✅ Starts Airbyte
- ✅ Starts Airflow + dbt-runner
- ✅ Configures Airbyte source, destination, and connection
- ✅ Sets Airflow variable `airbyte_connection_id`

### Step 2: Verify Services

```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "airbyte|airflow|dbt"
```

### Step 3: Access UIs

- **Airbyte**: http://localhost:8000 → Verify connection is created
- **Airflow**: http://localhost:8080 → Check `elt_pipeline` DAG exists

---

## ▶️ Running the Pipeline

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
│ dbt_run_staging          │ ✓ success             │ 2s                               │
│ dbt_run_marts            │ ✓ success             │ 2s                               │
│ dbt_run_gold             │ ✓ success             │ 2s                               │
│ dbt_test                 │ ✓ success             │ 2s                               │
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
# Run all models
docker exec dbt-runner dbt run

# Run specific layer
docker exec dbt-runner dbt run --select staging
docker exec dbt-runner dbt run --select marts
docker exec dbt-runner dbt run --select gold

# Run tests
docker exec dbt-runner dbt test
```

### Pipeline Tasks Explained

| Task | Description | Duration |
|------|-------------|----------|
| `check_data_source_mode` | Decides: Airbyte sync or seed data | <1s |
| `trigger_airbyte_sync` | Calls Airbyte API, waits for sync completion | 30-60s |
| `seed_raw_data` | Loads test SQL (only if Airbyte not configured) | <1s |
| `dbt_run_staging` | Creates `staging.*` views | ~2s |
| `dbt_run_marts` | Creates `marts.dim_users`, `marts.dim_products` tables | ~2s |
| `dbt_run_gold` | Creates `gold.gold_user_purchases` table | ~2s |
| `dbt_test` | Validates data quality (not null, unique, relationships) | ~2s |
| `data_loaded` | Join point — waits for whichever data source completed | <1s |
| `pipeline_complete` | Logs completion summary | <1s |

---

## 📊 Query Examples

### Connect to Database

```bash
docker exec -it postgres psql -U postgres -d airbyte_raw
```

### Gold Layer Queries

#### Top Spenders
```sql
SELECT full_name, total_spent, total_purchases, avg_purchase_value
FROM gold.gold_user_purchases
ORDER BY total_spent DESC
LIMIT 10;
```

#### High Return Rate Customers
```sql
SELECT full_name, return_rate_pct, total_returns, total_purchases
FROM gold.gold_user_purchases
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
FROM gold.gold_user_purchases
ORDER BY total_spent DESC;
```

#### Recent Purchasers
```sql
SELECT full_name, last_purchased_product, last_purchased_price, last_purchase_at
FROM gold.gold_user_purchases
WHERE last_purchase_at > NOW() - INTERVAL '30 days'
ORDER BY last_purchase_at DESC;
```

#### Geographic Analysis
```sql
SELECT city, state, country_code, COUNT(*) as customers, SUM(total_spent) as revenue
FROM gold.gold_user_purchases
GROUP BY city, state, country_code
ORDER BY revenue DESC;
```

---

## 👁️ Visualizing Results

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
  "SELECT user_id, full_name, total_purchases, total_spent FROM marts.dim_users LIMIT 10;"

echo "=== GOLD LAYER ===" && \
docker exec postgres psql -U postgres -d airbyte_raw -c \
  "SELECT full_name, total_spent, avg_purchase_value, return_rate_pct FROM gold.gold_user_purchases LIMIT 10;"
```

### Generate dbt Documentation

```bash
# Generate and serve dbt docs (includes lineage graph)
docker exec dbt-runner dbt docs generate
docker exec -d dbt-runner dbt docs serve --port 8081

# Open in browser
open http://localhost:8081
```

---

## 🛡️ Data Quality

### Test Coverage

The project includes **44 dbt tests** across all layers, validating structural integrity and referential consistency.

| Layer | Model | Tests | What's Validated |
|-------|-------|-------|------------------|
| **Sources** | `_airbyte_raw_*` (3 tables) | 3 | `_airbyte_data` is not null |
| **Staging** | `stg_users` | 4 | `user_id` unique + not null, `email` unique + not null, `full_name` not null, `age` not null |
| **Staging** | `stg_products` | 4 | `product_id` unique + not null, `make`/`model`/`price` not null |
| **Staging** | `stg_purchases` | 5 | `purchase_id` unique + not null, `user_id` FK → `stg_users`, `product_id` FK → `stg_products` |
| **Marts** | `dim_users` | 6 | `user_id` unique + not null + FK → `stg_users`, `full_name`/`email`/`total_purchases`/`total_spent` not null |
| **Marts** | `dim_products` | 5 | `product_id` unique + not null + FK → `stg_products`, `make`/`model`/`price` not null |
| **Gold** | `gold_user_purchases` | 7 | `user_id` unique + not null + FK → `dim_users`, `email` unique + not null, all metrics not null |
| | | **44** | |

### Test Types Used

| Type | Count | Purpose |
|------|-------|---------|
| `not_null` | 24 | No missing values in critical columns |
| `unique` | 11 | No duplicate keys or identifiers |
| `relationships` | 6 | Referential integrity across layers (staging → marts → gold) |
| Source tests | 3 | Raw data has content |

### Running Tests

```bash
# Run all tests
docker exec dbt-runner dbt test

# Run tests for a specific layer
docker exec dbt-runner dbt test --select staging
docker exec dbt-runner dbt test --select marts
docker exec dbt-runner dbt test --select gold

# Run tests for a specific model
docker exec dbt-runner dbt test --select dim_users
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

## 🔍 Troubleshooting

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

## 📁 Project Structure

```
dbt-airbyte/
├── docker-compose.yaml          # dbt + Airflow containers
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
│       ├── staging/             # stg_users, stg_products, stg_purchases (+ schema.yml tests)
│       ├── marts/               # dim_users, dim_products (+ schema.yml tests)
│       └── gold/                # gold_user_purchases (+ schema.yml tests)
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

## ⚠️ Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **PostgreSQL-specific SQL** | Gold model uses `DISTINCT ON` (Postgres-only syntax). Cannot port directly to Snowflake/BigQuery/Redshift. | Rewrite with `ROW_NUMBER()` window function for warehouse portability. |
| **Airbyte version lock** | Connector definition IDs in `configure_airbyte.py` are hardcoded for Airbyte OSS v0.50.5. Different versions use different UUIDs. | Re-inspect via `/api/v1/*Definitions/list` after upgrading Airbyte. |
| **No `description` in `dbt_project.yml`** | dbt 1.9 rejects project-level `description` field (`Additional properties are not allowed`). Supported in dbt 1.10+. | Descriptions live in individual `schema.yml` files instead. |
| **No Docker images past dbt 1.9** | `ghcr.io/dbt-labs/dbt-postgres` registry tops out at `1.9.0`. Upgrading to 1.10+ requires a custom Dockerfile. | Build from `python:3.12-slim` + `pip install dbt-core dbt-postgres`. |
| **Hardcoded credentials** | POC uses plaintext credentials (`dbt_password`, `airbyte_password`). Not suitable for production. | Use a secrets manager (Vault, AWS Secrets Manager). |
| **full_refresh only** | Every sync replaces all data. Acceptable for demo-scale; unsustainable for large datasets. | Switch to incremental + dedup sync mode. |

---

## 🚢 Extending to Production

This POC is intentionally simple. Here's what a production deployment would add:

- **Incremental syncs** — switch from full_refresh to incremental + dedup for large datasets
- **Secrets management** — replace hardcoded POC credentials with a vault (e.g., HashiCorp Vault, AWS Secrets Manager)
- **CI/CD** — add dbt slim CI (`dbt build --select state:modified+`) and Airflow DAG validation
- **Monitoring** — add Airflow alerting, dbt source freshness checks, data observability tooling
- **Scaling** — swap PostgreSQL for a cloud warehouse (Snowflake, BigQuery, Redshift); Airbyte Cloud for managed connectors

---

## 🗺️ Roadmap

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full implementation roadmap covering:

1. **Testing Depth** — `dbt build`, unit tests, source freshness, model contracts
2. **Data Observability** — Elementary (dbt-native quality dashboard with anomaly detection)
3. **SQL Quality Gates** — SQLFluff linting + pre-commit hooks
4. **CI/CD Pipeline** — GitHub Actions with slim CI (`state:modified+`)
5. **Governance** — Exposures, groups, and access control for multi-team collaboration

---

## 📚 Resources

- [Airbyte Documentation](https://docs.airbyte.com/)
- [Airbyte Faker Connector](https://docs.airbyte.com/integrations/sources/faker)
- [dbt Documentation](https://docs.getdbt.com/)
- [Airflow Documentation](https://airflow.apache.org/docs/)

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.
