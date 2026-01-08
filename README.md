# Airbyte + dbt POC

Minimalistic Modern Data Stack POC using Airbyte **Sample Data (Faker)** connector, **dbt**, and **Airflow** orchestration with your existing PostgreSQL server.

## 📊 Data Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AIRFLOW ORCHESTRATION                            │
│                         (elt_pipeline DAG)                              │
└────────┬────────────────────┬────────────────────┬─────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  1. SEED DATA   │──▶│  2. DBT RUN     │──▶│  3. DBT TEST    │
│  (Faker → Raw)  │   │  staging→marts  │   │  (validation)   │
│                 │   │  →gold          │   │                 │
└────────┬────────┘   └────────┬────────┘   └─────────────────┘
         │                     │
         ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         POSTGRESQL                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ airbyte_raw │  │   staging   │  │    marts    │  │    gold     │     │
│  │  (raw JSON) │─▶│   (views)   │─▶│  (tables)   │─▶│  (tables)   │     │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
dbt-airbyte/
├── docker-compose.yaml          # dbt + Airflow containers
├── airflow/
│   └── dags/
│       └── elt_pipeline.py      # Orchestration DAG
├── profiles/
│   └── profiles.yml             # dbt connection profile
├── dbt_project/
│   ├── dbt_project.yml
│   └── models/
│       ├── sources.yml          # Airbyte raw data sources
│       ├── staging/             # Raw → cleaned views
│       │   ├── stg_users.sql
│       │   ├── stg_products.sql
│       │   └── stg_purchases.sql
│       ├── marts/               # Business dimension tables
│       │   └── dim_users.sql
│       └── gold/                # Analytics-ready tables
│           └── gold_user_purchases.sql
├── scripts/
│   ├── setup.sh                 # One-click setup script
│   ├── init_databases.sql
│   ├── init_dbt_analytics_schemas.sql
│   ├── init_airbyte_raw_permissions.sql
│   └── seed_test_data.sql
└── README.md
```

## 🚀 Quick Start

### One-Command Setup

```bash
# Full setup (databases + containers)
./scripts/setup.sh

# Setup + load test data
./scripts/setup.sh --seed

# Teardown everything
./scripts/setup.sh --clean
```

### Manual Setup (Alternative)

```bash
# Create databases and users
docker exec -i n8n-postgres psql -U postgres -f - < scripts/init_databases.sql

# Create dbt schemas (staging, marts, gold)
docker exec -i n8n-postgres psql -U postgres -d dbt_analytics -f - < scripts/init_dbt_analytics_schemas.sql

# Set permissions on airbyte_raw database
docker exec -i n8n-postgres psql -U postgres -d airbyte_raw -f - < scripts/init_airbyte_raw_permissions.sql
```

### 2. Start Services

```bash
docker compose up -d
```

### 3. Access UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airflow** | http://localhost:8080 | admin / admin |
| **Airbyte** (optional) | http://localhost:8000 | - |

### 4. Run the Pipeline

**Option A: Via Airflow UI (Recommended)**
1. Open http://localhost:8080
2. Find `elt_pipeline` DAG
3. Toggle ON and click "Trigger DAG"

**Option B: Via CLI**
```bash
# Trigger the DAG
docker exec airflow airflow dags trigger elt_pipeline

# Or run dbt manually
docker exec dbt-runner dbt run
docker exec dbt-runner dbt test
```

---

## 🔄 Pipeline Flow

| Step | Task | Description |
|------|------|-------------|
| 1 | `seed_raw_data` | Load Faker data into `airbyte_raw` |
| 2 | `dbt_run_staging` | Transform raw JSON → typed views |
| 3 | `dbt_run_marts` | Build dimension tables |
| 4 | `dbt_run_gold` | Create analytics-ready tables |
| 5 | `dbt_test` | Validate data quality |
| 6 | `pipeline_complete` | Log success |

---

## 🔌 Airbyte Sample Data Connector (Optional)

The POC works with seed data, but you can connect real Airbyte:

| Stream | Description | Key Fields |
|--------|-------------|------------|
| `users` | Fake user profiles | id, name, email, address, occupation |
| `products` | Fake car catalog | id, make, model, year, price |
| `purchases` | Transactions | id, user_id, product_id, purchased_at |

**Airbyte Destination Config:**
| Field | Value |
|-------|-------|
| Host | `172.17.0.1` (Linux) / `host.docker.internal` (Mac/Win) |
| Port | `5432` |
| Database | `airbyte_raw` |
| Username | `airbyte_user` |
| Password | `airbyte_password` |

---

## 📊 Gold Layer Output

The final `gold.gold_user_purchases` table contains:

| Column | Description |
|--------|-------------|
| user_id | Unique user identifier |
| full_name | User's full name |
| email | Email address |
| total_purchases | Count of purchases |
| total_spent | Sum of purchase amounts |
| total_returns | Count of returned items |
| avg_purchase_value | Average order value |
| return_rate_pct | Return rate percentage |
| last_purchased_product | Most recent product bought |
| refreshed_at | Pipeline run timestamp |

---

## 🧹 Cleanup

```bash
# Stop all containers
docker compose down

# Drop POC databases
docker exec -i n8n-postgres psql -U postgres -c "DROP DATABASE IF EXISTS airbyte_raw;"
docker exec -i n8n-postgres psql -U postgres -c "DROP DATABASE IF EXISTS dbt_analytics;"
docker exec -i n8n-postgres psql -U postgres -c "DROP USER IF EXISTS dbt_user;"
docker exec -i n8n-postgres psql -U postgres -c "DROP USER IF EXISTS airbyte_user;"
```

---

## 📚 Resources

- [Airflow Documentation](https://airflow.apache.org/docs/)
- [dbt Documentation](https://docs.getdbt.com/)
- [Airbyte Sample Data Connector](https://docs.airbyte.com/integrations/sources/faker)
