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
4. dbt + Airflow containers join `n8n-network` to access existing postgres
5. dbt layers: staging (views) → marts (tables) → gold (tables)

## Quick Commands
```bash
# 1. Init databases (run once)
docker exec -i n8n-postgres psql -U n8n_user -d postgres < scripts/init_databases.sql
docker exec -i n8n-postgres psql -U n8n_user -d dbt_analytics < scripts/init_dbt_analytics_schemas.sql
docker exec -i n8n-postgres psql -U n8n_user -d airbyte_raw < scripts/init_airbyte_raw_permissions.sql

# 2. Seed test data (optional - skip if using Airbyte)
docker exec -i n8n-postgres psql -U n8n_user -d airbyte_raw < scripts/seed_test_data.sql

# 3. Start services (dbt + Airflow)
docker compose up -d

# 4. Run via Airflow (recommended)
# Open http://localhost:8080 → Trigger elt_pipeline DAG

# 5. Or run dbt manually
docker exec dbt-runner dbt debug
docker exec dbt-runner dbt run
docker exec dbt-runner dbt test
```

## Services
| Service | URL | Credentials |
|---------|-----|-------------|
| Airflow | http://localhost:8080 | admin / admin |
| Airbyte (optional) | http://localhost:8000 | - |

## Airbyte Source Config (Sample Data)
| Field | Value |
|-------|-------|
| Count | `100` |
| Seed | `42` (reproducible) |

## Airbyte Destination Config (PostgreSQL)
| Field | Value |
|-------|-------|
| Host | `172.17.0.1` (Linux) or `host.docker.internal` (Mac/Win) |
| Port | `5432` |
| Database | `airbyte_raw` |
| User | `airbyte_user` |
| Password | `airbyte_password` |