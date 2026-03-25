# dbt-airbyte — Project Reference

## Overview

End-to-end ELT data platform built on Airbyte + dbt 1.9 + Airflow + PostgreSQL. Airbyte
ingests raw data (or seeds substitute in dev); dbt transforms it through three layers
(staging → marts → gold); Airflow orchestrates the pipeline with branch logic for
Airbyte vs seed mode. All dbt execution runs inside a Docker container (`dbt-runner`).

## Stack

| Component | Version / Tool | Notes |
|-----------|---------------|-------|
| dbt | 1.9.0 (Critical Support) | `dbt build` for interleaved execution |
| Database | PostgreSQL | Target for all dbt models |
| Ingestion | Airbyte | Branch: real ingest vs seed fallback |
| Orchestration | Airflow | DAG with branch logic |
| SQL linting | SQLFluff | UPPER keywords, explicit aliases, spaced JSON ops |
| CI/CD | GitHub Actions | 2 parallel jobs: SQLFluff lint + dbt parse |
| Pre-commit | pre-commit hooks | SQLFluff enforced before commit |

## Key Commands

```bash
# Run full pipeline (interleaved models + tests in DAG order)
docker exec dbt-runner dbt build

# Run a specific layer
docker exec dbt-runner dbt build --select staging
docker exec dbt-runner dbt build --select marts
docker exec dbt-runner dbt build --select gold

# Tests only
docker exec dbt-runner dbt test

# Lint SQL
sqlfluff lint dbt_project/models/
sqlfluff fix dbt_project/models/

# dbt docs
docker exec dbt-runner dbt docs generate
docker exec dbt-runner dbt docs serve

# Start the full stack
./start.sh
```

## Project Structure

```
dbt_project/
  models/
    staging/       # Views: raw source cleaning (stg_users, stg_products, stg_purchases)
    marts/         # Tables: business dims with contracts (dim_users, dim_products)
    gold/          # Tables: aggregated facts with contracts (gold_user_purchases)
  dbt_project.yml
profiles/
  profiles.yml     # PostgreSQL connection config
airflow/           # DAG definitions
airbyte/           # Airbyte connection configs
docker-compose.yaml
docs/              # Roadmap, playbooks, quick-reference
```

## Conventions

This project follows the dbt engineering methodology defined in `.claude/skills/dbt-engineering/`.

Key conventions enforced:
- **SQL style**: UPPER keywords, explicit `AS` aliases, spaced JSON operators — enforced by SQLFluff
- **Architecture**: three-layer model hierarchy — staging (views) → marts (tables) → gold (tables)
- **Contracts**: enforced on all mart and gold models (`dim_users`, `dim_products`, `gold_user_purchases`)
- **Versioning**: mart and gold models at v1 with `defined_in` preserving SQL file names
- **Execution**: `dbt build` for interleaved model + test execution (bad data never propagates)
- **Tests**: 54 total — 44 data tests + 4 unit tests + 6 contract checks

## Skills

| Skill | When to load |
|-------|-------------|
| `dbt-engineering` | Auto-invoked when working on dbt models, tests, YAML, SQL, materializations, contracts, or CI/CD. Contains: project structure, SQL style, testing strategy, materialization decisions, governance, CI/CD, performance, maintenance, and anti-patterns. |

## Documentation

| File | Contents |
|------|----------|
| `docs/ROADMAP.md` | Project roadmap and current phase status |
| `docs/dbt-state-of-the-art-2025.md` | dbt ecosystem survey (2025) |
| `docs/dbt-production-playbook-2025.md` | Advanced maintenance patterns |
| `docs/PRODUCTION-QUICK-REFERENCE.md` | Quick-lookup decision trees |
| `docs/RESOURCES-AND-TOOLS.md` | Tooling catalog |
