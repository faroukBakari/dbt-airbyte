# Plan: Add Airbyte via Docker Compose

## Progress Checklist

- [x] **Step 1:** Add Airbyte to Docker Compose
  - [x] 1.1: Create `docker-compose.airbyte.yaml` with Airbyte services
  - [x] 1.2: Create `.env.airbyte` with environment variables
  - [x] 1.3: Validate compose file syntax

- [x] **Step 2:** Update `setup.sh` with Airbyte Support
  - [x] 2.1: Add `--no-airbyte` flag (Airbyte enabled by default)
  - [x] 2.2: Add `start_airbyte()` function
  - [x] 2.3: Add `wait_for_airbyte()` health check function
  - [x] 2.4: Update `check_all_services()` for Airbyte status
  - [x] 2.5: Update `print_service_urls()` with Airbyte row
  - [x] 2.6: Validate bash syntax

- [x] **Step 3:** Update Airflow DAG for Airbyte Integration
  - [x] 3.1: Add Airbyte API trigger task (BashOperator + curl)
  - [x] 3.2: Add conditional logic for seed vs Airbyte mode
  - [x] 3.3: Validate Python syntax

- [x] **Step 4:** Verify dbt Sources Configuration
  - [x] 4.1: Confirm `sources.yml` matches Airbyte raw table naming

- [x] **Step 5:** Update Documentation
  - [x] 5.1: Update `copilot-instructions.md` with Airbyte setup steps
  - [x] 5.2: Update README.md with new architecture

---

## ✅ PLAN COMPLETE

All steps have been implemented and validated.

### Summary of Changes

| File | Status |
|------|--------|
| `docker-compose.airbyte.yaml` | ✅ Created (6 Airbyte containers) |
| `airbyte/temporal/dynamicconfig/development.yaml` | ✅ Created (required config) |
| `scripts/setup.sh` | ✅ Updated (Airbyte default, `--no-airbyte` flag) |
| `airflow/dags/elt_pipeline.py` | ✅ Updated (branching logic) |
| `.github/copilot-instructions.md` | ✅ Updated (Airbyte docs) |
| `README.md` | ✅ Updated (architecture + setup guide) |

### Next Steps (Manual)

1. Run `./scripts/setup.sh` (Airbyte enabled by default)
2. Configure Airbyte Source/Destination/Connection in UI
3. Copy Connection ID to Airflow Variable
4. Trigger pipeline via Airflow

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         n8n-network                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │ n8n-postgres│◄───│   Airbyte   │    │   Airflow   │                 │
│  │   :5432     │    │   :8000     │    │   :8080     │                 │
│  └──────▲──────┘    └──────┬──────┘    └──────┬──────┘                 │
│         │                  │                  │                         │
│         │    ┌─────────────┴──────────────────┘                        │
│         │    │                                                          │
│  ┌──────┴──────┐                                                        │
│  │ dbt-runner  │  staging → marts → gold                               │
│  └─────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```
