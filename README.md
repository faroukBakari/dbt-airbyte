# Airbyte + dbt POC

Minimalistic Modern Data Stack POC using **Airbyte** (Extract/Load) + **dbt** (Transform) + **Airflow** (Orchestration) with your existing PostgreSQL container.

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         n8n-network                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │ n8n-postgres│◄───│   Airbyte   │    │   Airflow   │                 │
│  │   :5432     │    │   :8000     │    │   :8080     │                 │
│  └──────▲──────┘    └─────────────┘    └──────┬──────┘                 │
│         │                                      │                        │
│         └──────────────────────────────────────┘                        │
│  ┌─────────────┐                                                        │
│  │ dbt-runner  │  staging → marts → gold                               │
│  └─────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
dbt-airbyte/
├── docker-compose.yaml          # dbt + Airflow containers
├── docker-compose.airbyte.yaml  # Airbyte containers (6 services)
├── airbyte/                     # Airbyte config files
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
│       ├── marts/               # Business dimension tables
│       └── gold/                # Analytics-ready tables
├── scripts/
│   └── setup.sh                 # One-click setup script
└── README.md
```

## 🚀 Quick Start

### Full Setup (Default - includes Airbyte)

```bash
./scripts/setup.sh
```

This will:
1. ✅ Create databases (`airbyte_raw`, `dbt_analytics`)
2. ✅ Create users (`airbyte_user`, `dbt_user`)
3. ✅ Start Airbyte (6 containers)
4. ✅ Start dbt + Airflow

### Setup without Airbyte

```bash
./scripts/setup.sh --no-airbyte
```

### Setup with Seed Data (No Airbyte)

```bash
./scripts/setup.sh --seed
```

Uses pre-loaded test data instead of Airbyte connector.

### Cleanup

```bash
./scripts/setup.sh --clean
```

---

## 🌐 Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airbyte** | http://localhost:8000 | airbyte / password |
| **Airflow** | http://localhost:8080 | admin / admin |
| **PostgreSQL** | localhost:5432 | n8n_user |

---

## 🔧 Airbyte Configuration (After setup)

### Step 1: Create Source → Sample Data (Faker)

| Field | Value |
|-------|-------|
| Count | `100` |
| Seed | `42` (reproducible) |

### Step 2: Create Destination → PostgreSQL

| Field | Value |
|-------|-------|
| Host | `n8n-postgres` |
| Port | `5432` |
| Database | `airbyte_raw` |
| User | `airbyte_user` |
| Password | `airbyte_password` |

### Step 3: Create Connection

1. Link **Faker source** → **PostgreSQL destination**
2. Run the first sync
3. Copy the **Connection ID** from the URL (e.g., `1ab174f8-fa2c-...`)

### Step 4: Configure Airflow Variable

1. Open Airflow UI: http://localhost:8080
2. Go to **Admin → Variables**
3. Add new variable:
   - **Key**: `airbyte_connection_id`
   - **Value**: `<your-connection-id>`

---

## 🔄 Data Pipeline

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Airbyte       │      │   dbt           │      │   dbt           │
│   (OR seed)     │ ───▶ │   staging       │ ───▶ │   marts/gold    │
│   Raw Data      │      │   (views)       │      │   (tables)      │
└─────────────────┘      └─────────────────┘      └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
    airbyte_raw          dbt_analytics.staging    dbt_analytics.marts
    ._airbyte_raw_*      .stg_*                   .dim_*, .gold_*
```

### Data Streams (Faker Connector)

| Stream | Description | Key Fields |
|--------|-------------|------------|
| `users` | Fake user profiles | id, name, email, address, occupation |
| `products` | Fake car catalog | id, make, model, year, price |
| `purchases` | Transactions | id, user_id, product_id, purchased_at |

---

## 📊 Gold Layer Output

The final `gold.gold_user_purchases` table:

| Column | Description |
|--------|-------------|
| user_id | Unique user identifier |
| full_name | User's full name |
| email | Email address |
| total_purchases | Count of purchases |
| total_spent | Sum of purchase amounts |
| avg_purchase_value | Average order value |
| last_purchased_product | Most recent product bought |
| refreshed_at | Pipeline run timestamp |

---

## 🛠️ Manual Commands

```bash
# dbt commands
docker exec dbt-runner dbt debug
docker exec dbt-runner dbt run
docker exec dbt-runner dbt test

# Check service status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# View logs
docker logs -f airbyte-webapp
docker logs -f airflow
docker logs -f dbt-runner
```

---

## 📚 Resources

- [Airbyte Sample Data (Faker) Connector](https://docs.airbyte.com/integrations/sources/faker)
- [dbt Documentation](https://docs.getdbt.com/)
- [Airflow Documentation](https://airflow.apache.org/docs/)
