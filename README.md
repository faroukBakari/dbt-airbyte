# Airbyte + dbt POC

A minimalistic **Modern Data Stack** proof-of-concept demonstrating end-to-end ELT (Extract, Load, Transform) using:

- **Airbyte** — Data extraction & loading (EL)
- **dbt Core** — Data transformation (T)
- **Airflow** — Pipeline orchestration
- **PostgreSQL** — Data warehouse (reusing existing `postgres`)

> 🎯 **Goal**: Ingest fake e-commerce data (users, products, purchases), transform it through staging → marts → gold layers, and produce analytics-ready tables.

---

## 📑 Table of Contents

- [Quick Start](#-quick-start)
- [Prerequisites](#-prerequisites)
- [Architecture](#-architecture)
- [ELT Pipeline Explained](#-elt-pipeline-explained)
- [Setup Guide](#-setup-guide)
- [Running the Pipeline](#-running-the-pipeline)
- [Query Examples](#-query-examples)
- [Visualizing Results](#-visualizing-results)
- [Troubleshooting](#-troubleshooting)
- [Resources](#-resources)

---

## 🚀 Quick Start

```bash
# 1. Full setup (includes Airbyte)
./scripts/setup.sh

# 2. Run the ELT pipeline
./scripts/run_pipeline.sh

# 3. Query the results
docker exec -it postgres psql -U db_user -d airbyte_raw \
  -c "SELECT full_name, total_spent, avg_purchase_value FROM gold.gold_user_purchases;"
```

### Alternative Setup Modes

```bash
# Setup WITHOUT Airbyte (lighter, uses seed data)
./scripts/setup.sh --seed

# Cleanup everything
./scripts/setup.sh --clean
```

---

## 📋 Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | 20.10+ | With Docker Compose v2 |
| Docker Network | `poc-network` | Must exist before setup |
| PostgreSQL Container | `postgres` | Existing container on port 5432 |

### Verify Prerequisites

```bash
# Check Docker
docker --version

# Check poc-network exists
docker network ls | grep poc-network

# Check postgres is running
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
│  │                     postgres :5432                      │           │
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
| **PostgreSQL** | localhost:5432 | `db_user` (superuser) |

### Databases & Users

| Database | User | Purpose |
|----------|------|---------|
| `airbyte_raw` | `airbyte_user` | Raw data from Airbyte + dbt transforms |
| `dbt_analytics` | `dbt_user` | (Reserved for future separation) |

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
│  │  (users)    │  │     ┌─────────────┐    ┌─────────────┐                 │
│  └─────────────┘  │     │   STAGING   │    │    MARTS    │                 │
│  ┌─────────────┐  │     │   (views)   │    │  (tables)   │    ┌─────────┐  │
│  │ Faker Source│──┼────▶│             │───▶│             │───▶│  GOLD   │  │
│  │ (products)  │  │     │ • stg_users │    │ • dim_users │    │(tables) │  │
│  └─────────────┘  │     │ • stg_prods │    │             │    │         │  │
│  ┌─────────────┐  │     │ • stg_purch │    │             │    │ • gold_ │  │
│  │ Faker Source│──┘     └─────────────┘    └─────────────┘    │  user_  │  │
│  │ (purchases) │                                              │  purch  │  │
│  └─────────────┘                                              └─────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

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
-- Aggregates purchase activity per user
SELECT user_id, full_name, total_purchases, total_spent, first_purchase_at
FROM marts.dim_users;
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
- ✅ Creates databases (`airbyte_raw`, `dbt_analytics`)
- ✅ Creates users with proper grants (`airbyte_user`, `dbt_user`)
- ✅ Starts Airbyte (6 containers)
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
| `dbt_run_marts` | Creates `marts.dim_users` table | ~2s |
| `dbt_run_gold` | Creates `gold.gold_user_purchases` table | ~2s |
| `dbt_test` | Validates data quality (not null, unique, etc.) | ~2s |

---

## 📊 Query Examples

### Connect to Database

```bash
docker exec -it postgres psql -U db_user -d airbyte_raw
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
docker exec postgres psql -U db_user -d airbyte_raw -c \
  "SELECT '_airbyte_raw_users' as table_name, COUNT(*) FROM _airbyte_raw_users
   UNION ALL SELECT '_airbyte_raw_products', COUNT(*) FROM _airbyte_raw_products
   UNION ALL SELECT '_airbyte_raw_purchases', COUNT(*) FROM _airbyte_raw_purchases;"

echo "=== STAGING LAYER ===" && \
docker exec postgres psql -U db_user -d airbyte_raw -c \
  "SELECT user_id, full_name, occupation, city FROM staging.stg_users LIMIT 5;"

echo "=== MARTS LAYER ===" && \
docker exec postgres psql -U db_user -d airbyte_raw -c \
  "SELECT user_id, full_name, total_purchases, total_spent FROM marts.dim_users;"

echo "=== GOLD LAYER ===" && \
docker exec postgres psql -U db_user -d airbyte_raw -c \
  "SELECT full_name, total_spent, avg_purchase_value, return_rate_pct FROM gold.gold_user_purchases;"
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

**Cause:** Querying wrong database. dbt writes to `airbyte_raw`, not `dbt_analytics`.

**Fix:** Connect to `airbyte_raw`:
```bash
docker exec -it postgres psql -U db_user -d airbyte_raw
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
├── docker-compose.airbyte.yaml  # Airbyte containers (6 services)
├── airflow/
│   └── dags/
│       └── elt_pipeline.py      # Orchestration DAG
├── dbt_project/
│   ├── dbt_project.yml          # dbt configuration
│   └── models/
│       ├── sources.yml          # Source definitions
│       ├── staging/             # stg_users, stg_products, stg_purchases
│       ├── marts/               # dim_users
│       └── gold/                # gold_user_purchases
├── profiles/
│   └── profiles.yml             # dbt connection profile
├── scripts/
│   ├── setup.sh                 # One-click setup
│   ├── run_pipeline.sh          # Pipeline runner with monitoring
│   ├── configure_airbyte.py     # Airbyte auto-configuration
│   └── seed_test_data.sql       # Sample data for testing
└── README.md
```

---

## 📚 Resources

- [Airbyte Documentation](https://docs.airbyte.com/)
- [Airbyte Faker Connector](https://docs.airbyte.com/integrations/sources/faker)
- [dbt Documentation](https://docs.getdbt.com/)
- [Airflow Documentation](https://airflow.apache.org/docs/)

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.
