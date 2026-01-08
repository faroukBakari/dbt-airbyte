# Airbyte + dbt POC - Copilot Instructions

## Context
Minimalistic POC for a Modern Data Stack using **Airbyte** (EL) + **dbt Core** (T) + **Airflow** (orchestration) reusing the **existing PostgreSQL** container (`n8n-postgres`).

## Data Source
**Airbyte Sample Data (Faker)** connector — generates fake e-commerce data with:
- `users` — user profiles (name, email, address, occupation)
- `products` — car catalog (make, model, year, price)
- `purchases` — transactions linking users to products

✅ No API keys required!

## Existing Infrastructure
- **PostgreSQL Container**: `n8n-postgres` on port 5432
- **Docker Network**: `n8n-network`
- **Superuser**: `n8n_user` (owner of all databases)

## POC Requirements
1. **DO NOT** create a new PostgreSQL container
2. Create isolated databases: `airbyte_raw` and `dbt_analytics`
3. Create dedicated users: `airbyte_user` and `dbt_user`
4. dbt + Airflow + Airbyte containers join `n8n-network` to access existing postgres
5. dbt layers: staging (views) → marts (tables) → gold (tables)

## Quick Commands
```bash
# Full setup WITH Airbyte (default)
./scripts/setup.sh

# Setup without Airbyte
./scripts/setup.sh --no-airbyte

# Setup with seed data (no Airbyte)
./scripts/setup.sh --seed

# Cleanup
./scripts/setup.sh --clean

# Manual dbt commands
docker exec dbt-runner dbt debug
docker exec dbt-runner dbt run
docker exec dbt-runner dbt test
```

## Services
| Service | URL | Credentials |
|---------|-----|-------------|
| Airbyte | http://localhost:8000 | airbyte / password |
| Airflow | http://localhost:8080 | admin / admin |
| PostgreSQL | localhost:5432 | n8n_user |

## Airbyte Setup (Manual Steps after setup)

### 1. Create Source: Sample Data (Faker)
| Field | Value |
|-------|-------|
| Count | `100` |
| Seed | `42` (reproducible) |

### 2. Create Destination: PostgreSQL
| Field | Value |
|-------|-------|
| Host | `localhost` |
| Port | `5432` |
| Database | `airbyte_raw` |
| User | `airbyte_user` |
| Password | `airbyte_password` |

> ⚠️ **Important**: Use `localhost` (not `n8n-postgres`) because Airbyte connectors run with `--network host` where Docker DNS is unavailable.

### 3. Create Connection
- Link Faker source → PostgreSQL destination
- Copy the **Connection ID** from the URL (e.g., `1ab174f8-fa2c-...`)

### 4. Configure Airflow
- Go to Airflow UI → Admin → Variables
- Add: `airbyte_connection_id` = `<your-connection-id>`

## Architecture
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
