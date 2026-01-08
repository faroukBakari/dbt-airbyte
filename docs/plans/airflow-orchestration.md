# Implementation Plan: Add Airflow Orchestration to Complete POC

## Progress Checklist

- [x] **Step 1**: Add Airflow Services to Docker Compose
  - [x] Add Airflow standalone service
  - [x] Mount dbt project and DAGs folder
  - [x] Join n8n-network
- [ ] **Step 2**: Create Gold Layer in dbt
  - [x] Add models/gold/ folder
  - [x] Create gold_user_purchases.sql model
  - [x] Update dbt_project.yml with gold config
- [x] **Step 3**: Create Airflow DAG
  - [x] Create airflow/dags/ directory structure
  - [x] Create elt_pipeline.py DAG file
- [x] **Step 4**: Update Init Scripts for Gold Schema
  - [x] Add gold schema grants to init_databases.sql
- [x] **Step 5**: Update Documentation
  - [x] Update README.md with Airflow instructions
  - [x] Update copilot-instructions.md with new commands
- [x] **Step 6**: Validation
  - [x] Verify docker-compose syntax
  - [x] Verify dbt project compiles

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Airflow (Orchestrator)                          │
│                        elt_pipeline DAG                             │
└──────────┬──────────────────┬──────────────────┬───────────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
    ┌────────────┐    ┌────────────┐    ┌────────────┐
    │ seed_data  │───▶│  dbt_run   │───▶│ dbt_test   │
    │ (raw)      │    │ (staging → │    │ (validate) │
    │            │    │  marts →   │    │            │
    │            │    │  gold)     │    │            │
    └────────────┘    └────────────┘    └────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
    ┌─────────────────────────────────────────────────┐
    │              PostgreSQL (n8n-postgres)          │
    │  airbyte_raw │ dbt_analytics.staging │ .marts │ .gold │
    └─────────────────────────────────────────────────┘
```

---

## Step Details

### Step 1: Add Airflow Services to Docker Compose `[Risk: Medium]`
- Add Airflow with **standalone mode** (single container) for POC simplicity
- Mount dbt project into Airflow container for BashOperator execution
- Join n8n-network to access PostgreSQL and dbt-runner

### Step 2: Create Gold Layer in dbt `[Risk: Low]`
- Add new model folder `models/gold/`
- Create `gold_user_purchases.sql` — final analytics-ready table
- Update `dbt_project.yml` with gold layer config

### Step 3: Create Airflow DAG `[Risk: Medium]`
- Create `airflow/dags/elt_pipeline.py` with sequential tasks:
  1. seed_raw_data - Load test data into airbyte_raw
  2. dbt_run_staging - Transform raw → staging
  3. dbt_run_marts - Transform staging → marts
  4. dbt_run_gold - Transform marts → gold
  5. dbt_test - Validate data quality

### Step 4: Update Init Scripts for Gold Schema `[Risk: Low]`
- Add gold schema grants to init_databases.sql

### Step 5: Update Documentation `[Risk: Low]`
- Update README.md with Airflow UI access and DAG instructions
- Update copilot-instructions.md with new quick commands

### Step 6: Validation `[Risk: Low]`
- Verify docker-compose syntax
- Verify dbt project compiles
