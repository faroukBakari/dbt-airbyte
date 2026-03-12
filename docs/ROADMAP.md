# Roadmap: Data Quality & CI Maturity

> From working POC to team-ready, production-grade data platform.

This roadmap builds on the current state: Airbyte + dbt 1.9 + Airflow + PostgreSQL, with 44 passing tests across staging/marts/gold layers. Each phase adds a layer of maturity without changing the core architecture.

---

## Current State

| Component | Status |
|-----------|--------|
| ELT pipeline | End-to-end: Airbyte/seed → staging → marts → gold |
| dbt version | 1.9.0 (Critical Support) |
| Test coverage | 54 tests — 44 data tests + 4 unit tests + 6 contract checks |
| Execution model | `dbt build` (interleaved models + tests in DAG order) |
| Contracts | Enforced on marts (`dim_users`, `dim_products`) and gold (`gold_user_purchases`) |
| Versioning | All mart/gold models at v1, `defined_in` preserving SQL file names |
| Exposures | 3 declared downstream consumers (dashboard, analysis, ML pipeline) |
| Orchestration | Airflow DAG with branch logic (Airbyte vs seed mode) |
| Documentation | Column descriptions in all schema.yml files, dbt docs generate |
| CI/CD | None |

---

## Phase 1: Testing Depth

**Goal**: Prove business logic correctness and catch data drift — not just structural integrity.

### 1.1 — Switch to `dbt build` (interleaved execution)

**What**: Replace separate `dbt run --select <layer>` + `dbt test` tasks in the Airflow DAG with a single `dbt build` command.

**Why**: `dbt build` runs models and tests in DAG-interleaved order. If `dim_users` tests fail, `gold_user_purchases` is **skipped** — bad data never propagates downstream. The current setup runs all models first, then all tests, meaning a broken mart still feeds into gold before tests catch it.

**How**: Simplify the Airflow DAG:

```
Before (current):
  data_loaded → dbt_run_staging → dbt_run_marts → dbt_run_gold → dbt_test → pipeline_complete

After:
  data_loaded → dbt_build → pipeline_complete
```

The `dbt_build` task:
```bash
docker exec dbt-runner dbt build
```

This runs seeds → staging views → staging tests → mart tables → mart tests → gold tables → gold tests, in dependency order. A test failure at any layer stops downstream execution.

**Trade-off**: Loses per-layer visibility in Airflow. Mitigation: dbt's own logs show per-model status. For richer Airflow visibility, consider the `cosmos` package (Phase 5 — Future).

**Effort**: ~30 minutes. One task replaces five.

---

### 1.2 — Unit Tests (dbt 1.9 native)

**What**: Test transformation logic in isolation — without hitting the database. Prove that business calculations (return rate, average purchase value, total spent) are correct for known inputs.

**Why**: Current tests validate *data properties* (not null, unique). Unit tests validate *logic correctness*. A `not_null` test on `return_rate_pct` doesn't prove the formula is right — a unit test does.

**Where**: Create `dbt_project/models/gold/unit_tests.yml` (any `.yml` file under `models/` works).

**What to test**:

| Test | Model | Validates |
|------|-------|-----------|
| `test_return_rate_calculation` | `gold_user_purchases` | `return_rate_pct = total_returns / total_purchases * 100` |
| `test_avg_purchase_value` | `gold_user_purchases` | `avg_purchase_value = total_spent / total_purchases` |
| `test_user_with_no_returns` | `gold_user_purchases` | `return_rate_pct = 0` when `total_returns = 0` |
| `test_total_spent_aggregation` | `dim_users` | Sum of purchase amounts matches `total_spent` |
| `test_total_purchases_count` | `dim_users` | Count of purchase rows matches `total_purchases` |

**Syntax** (dbt 1.9):

```yaml
unit_tests:
  - name: test_return_rate_calculation
    description: Verify return rate percentage formula
    model: gold_user_purchases
    given:
      - input: ref('dim_users')
        rows:
          - {user_id: 1, full_name: "Test User", email: "test@test.com",
             total_purchases: 10, total_returns: 3, total_spent: 500.00,
             first_purchase_at: "2024-01-01", last_purchase_at: "2024-06-01"}
      - input: ref('dim_products')
        rows:
          - {product_id: 1, make: "TestMake", model: "TestModel",
             year: 2024, price: 50.00}
    expect:
      rows:
        - {user_id: 1, return_rate_pct: 30.0}
```

**Run**: `dbt test --select test_type:unit` (isolated) or included automatically in `dbt build`.

**Note**: Unit tests run *before* model materialization in `dbt build`. A failing unit test blocks the model from being built.

**Effort**: ~2 hours. YAML-only, no infrastructure changes.

---

### 1.3 — Source Freshness Checks

**What**: Verify that raw Airbyte data is recent before running transformations.

**Why**: If Airbyte sync failed silently or stalled, dbt would happily rebuild all models from stale data. Source freshness catches this at the gate.

**How**: Add `freshness` config to `dbt_project/models/sources.yml`:

```yaml
sources:
  - name: airbyte_raw
    database: airbyte_raw
    schema: public
    config:
      loaded_at_field: "cast(_airbyte_emitted_at as timestamp)"
    tables:
      - name: _airbyte_raw_users
        config:
          freshness:
            warn_after: {count: 12, period: hour}
            error_after: {count: 24, period: hour}
      - name: _airbyte_raw_products
        # ... same pattern
      - name: _airbyte_raw_purchases
        # ... same pattern
```

**Integration with Airflow**: Add a `dbt_source_freshness` task before `dbt_build`:

```
data_loaded → dbt_source_freshness → dbt_build → pipeline_complete
```

`dbt source freshness` exits non-zero on error-level staleness, which Airflow's `BashOperator` propagates as task failure — blocking downstream transforms.

**Column requirement**: `_airbyte_emitted_at` is a timestamp column that Airbyte adds to every raw table. Must be cast to `timestamp` if stored as text.

**Effort**: ~1 hour. YAML + one Airflow task.

---

### 1.4 — Model Contracts (marts and gold)

**What**: Enforce exact column names and types on materialized tables. If a model change breaks the schema, `dbt build` fails before bad data lands.

**Why**: Without contracts, a typo in a column alias or a type change silently propagates. Contracts make schema changes explicit and intentional — critical when multiple people work on the same models.

**Where**: Apply to `dim_users`, `dim_products`, and `gold_user_purchases` (materialized tables only — contracts don't work with views, so staging is excluded).

**Syntax** (in existing `schema.yml` files):

```yaml
models:
  - name: dim_users
    description: User dimension with purchase activity summary
    config:
      contract:
        enforced: true
    columns:
      - name: user_id
        description: Primary key — unique user identifier
        data_type: bigint
        # ... existing tests
      - name: full_name
        data_type: text
      - name: email
        data_type: text
      - name: total_purchases
        data_type: bigint
      - name: total_spent
        data_type: numeric
```

**Valid PostgreSQL data_types**: `int`, `bigint`, `smallint`, `numeric`, `numeric(p,s)`, `text`, `varchar`, `boolean`, `timestamp`, `timestamptz`, `date`, `uuid`, `jsonb`.

**Effort**: ~1 hour. Add `data_type` to existing column definitions + `contract.enforced` config.

---

## Phase 2: Data Observability

**Goal**: Continuous monitoring with historical trends — not just point-in-time pass/fail.

### 2.1 — Elementary (dbt-native observability)

**What**: Open-source dbt package that captures test results, model run metadata, and anomaly metrics into dedicated tables. Generates an HTML observability dashboard.

**Why**: Current test output is ephemeral — it prints to stdout and disappears. Elementary gives you a *time-series view* of data quality: when tests started failing, which models are slowing down, volume anomalies. This is the single most impressive thing to show in a demo.

**Setup**:

1. Create `dbt_project/packages.yml`:
   ```yaml
   packages:
     - package: elementary-data/elementary
       version: [">=0.20.0", "<0.21.0"]
   ```

2. Install: `docker exec dbt-runner dbt deps`

3. Add Elementary profile to `profiles/profiles.yml`:
   ```yaml
   elementary:
     target: dev
     outputs:
       dev:
         type: postgres
         host: "{{ env_var('DBT_HOST') }}"
         port: 5432
         user: "{{ env_var('DBT_USER') }}"
         password: "{{ env_var('DBT_PASSWORD') }}"
         dbname: "{{ env_var('DBT_DBNAME') }}"
         schema: elementary
   ```

4. Run Elementary models: `docker exec dbt-runner dbt run --select elementary`

5. Generate report (requires `edr` CLI — separate Python package):
   ```bash
   pip install elementary-data  # or uv add elementary-data
   edr report --profiles-dir ./profiles
   ```

**What you get**: An HTML dashboard showing test results over time, model execution durations, freshness status, and anomaly detection — all from data already captured by dbt.

**Models created**: Elementary materializes ~15 tables in an `elementary` schema: `elementary_test_results`, `dbt_models`, `dbt_run_results`, `dbt_invocations`, `data_monitoring_metrics`, etc.

**Effort**: ~3 hours (including Docker integration for `edr`).

---

## Phase 3: SQL Quality Gates

**Goal**: Consistent SQL style across the team. Code reviews focus on logic, not formatting.

### 3.1 — SQLFluff (linter + formatter)

**What**: SQL linter that understands dbt's Jinja2 templating. Enforces style rules, catches bugs (ambiguous references, missing GROUP BY columns), and auto-formats.

**Configuration** — `.sqlfluff` at project root:

```ini
[sqlfluff]
templater = jinja
dialect = postgres
max_line_length = 120
exclude_rules = LT05

[sqlfluff:templater:jinja]
apply_dbt_builtins = true

[sqlfluff:indentation]
indent_unit = space
tab_space_size = 4
indented_joins = false
indented_using_on = true

[sqlfluff:rules:capitalisation.keywords]
capitalisation_policy = upper

[sqlfluff:rules:capitalisation.functions]
extended_capitalisation_policy = upper
```

**Templater choice**:
- `jinja` (recommended for CI): No database connection needed. Understands `ref()`, `source()`, `config()` as builtins. Fast. Fails on complex custom macros from packages like `dbt_utils`.
- `dbt` (full fidelity): Requires `sqlfluff-templater-dbt` + a live database profile. Slower but handles all macros. Better for local development.

For this POC, `jinja` is sufficient — no complex macros.

**Usage**:
```bash
# Lint (check only)
sqlfluff lint dbt_project/models/

# Fix (auto-format)
sqlfluff fix dbt_project/models/

# Check specific file
sqlfluff lint dbt_project/models/gold/gold_user_purchases.sql
```

**Effort**: ~1 hour. Config file + run once to fix existing code.

### 3.2 — Pre-commit Hooks

**What**: Git hooks that run SQLFluff lint (and optionally YAML validation) before every commit.

**Configuration** — `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.3.0
    hooks:
      - id: sqlfluff-lint
        args: [--dialect, postgres]
        files: ^dbt_project/models/
      - id: sqlfluff-fix
        args: [--dialect, postgres, --force]
        files: ^dbt_project/models/
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
        args: [--allow-multiple-documents]
      - id: trailing-whitespace
      - id: end-of-file-fixer
```

**Effort**: ~30 minutes.

---

## Phase 4: CI/CD Pipeline

**Goal**: Every PR validates dbt changes automatically. Only modified models are tested.

### 4.1 — GitHub Actions: dbt Slim CI

**What**: A CI workflow that runs `dbt build --select state:modified+` on pull requests — only building and testing models that changed (plus their downstream dependents).

**How it works**:
1. Production `dbt build` saves `manifest.json` as a CI artifact after each successful run
2. PR workflow downloads the prod manifest
3. `dbt build --select state:modified+ --defer --state ./prod-manifest/` compares PR state against prod state
4. `--defer` resolves unchanged upstream `ref()`s against the prod manifest (no need to rebuild parents)

**Workflow** — `.github/workflows/dbt-ci.yml`:

```yaml
name: dbt CI

on:
  pull_request:
    paths:
      - 'dbt_project/**'
      - 'profiles/**'

jobs:
  dbt-ci:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: ci_test
          POSTGRES_USER: ci_user
          POSTGRES_PASSWORD: ci_password
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U ci_user"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dbt
        run: pip install dbt-core==1.9.0 dbt-postgres==1.9.0

      - name: Create CI schemas
        run: |
          PGPASSWORD=ci_password psql -h localhost -U ci_user -d ci_test -c \
            "CREATE SCHEMA IF NOT EXISTS staging;
             CREATE SCHEMA IF NOT EXISTS marts;
             CREATE SCHEMA IF NOT EXISTS gold;"

      - name: Download prod manifest
        uses: actions/download-artifact@v4
        with:
          name: prod-manifest
          path: ./prod-manifest/
        continue-on-error: true  # First run has no artifact yet

      - name: dbt deps
        run: cd dbt_project && dbt deps --profiles-dir ../profiles

      - name: SQLFluff lint
        run: sqlfluff lint dbt_project/models/ --dialect postgres
        continue-on-error: true  # Advisory in early adoption

      - name: dbt build (modified models only)
        run: |
          cd dbt_project
          if [ -f ../prod-manifest/manifest.json ]; then
            dbt build --select state:modified+ \
                      --defer \
                      --state ../prod-manifest/ \
                      --profiles-dir ../profiles \
                      --target ci
          else
            dbt build --profiles-dir ../profiles --target ci
          fi

      - name: Save manifest for future runs
        if: github.ref == 'refs/heads/master'
        uses: actions/upload-artifact@v4
        with:
          name: prod-manifest
          path: dbt_project/target/manifest.json
          retention-days: 90
```

**CI profile** — add to `profiles/profiles.yml`:

```yaml
dbt_airbyte_poc:
  target: dev
  outputs:
    dev:
      # ... existing config
    ci:
      type: postgres
      host: localhost
      port: 5432
      user: ci_user
      password: ci_password
      dbname: ci_test
      schema: public
      threads: 2
```

**What slim CI buys you**: Change `dim_users.sql` → CI builds only `dim_users` + `gold_user_purchases` (its downstream dependent), runs their tests, skips `stg_*` and `dim_products`. Fast, cheap, focused.

**Effort**: ~3 hours (workflow + CI profile + first manifest bootstrap).

### 4.2 — dbt Compile Check (no DB required)

**What**: A fast CI step that validates SQL syntax and Jinja2 compilation without a database connection.

**How**: `dbt parse` validates project structure, YAML schema, and ref/source resolution. `dbt compile` generates the compiled SQL. Neither requires a database.

**Use case**: Run on every PR as a fast gate before the full `dbt build` step. Catches typos, broken refs, and YAML errors in seconds.

```yaml
- name: dbt parse (syntax check)
  run: cd dbt_project && dbt parse --profiles-dir ../profiles
```

**Effort**: ~15 minutes. One CI step.

---

## Phase 5: Governance & Team Readiness

**Goal**: Multi-team ownership, impact analysis, and downstream visibility.

### 5.1 — Exposures

**What**: Declare downstream consumers of your dbt models — dashboards, reports, ML pipelines, applications. Shows up in dbt docs lineage graph.

**Why**: When someone changes `gold_user_purchases`, they should know *what breaks downstream*. Exposures make impact analysis visible without tribal knowledge.

**Syntax** — `dbt_project/models/exposures.yml`:

```yaml
exposures:
  - name: executive_kpi_dashboard
    type: dashboard
    description: Weekly executive dashboard showing customer LTV, retention, and revenue
    owner:
      name: Analytics Team
      email: analytics@company.com
    depends_on:
      - ref('gold_user_purchases')

  - name: product_performance_report
    type: analysis
    description: Monthly product sales and return rate analysis
    owner:
      name: Product Team
      email: product@company.com
    depends_on:
      - ref('dim_products')
      - ref('gold_user_purchases')
```

**Effort**: ~30 minutes. YAML-only.

### 5.2 — Groups & Access Control (dbt 1.9)

**What**: Assign models to team-owned groups. Restrict cross-group `ref()` access.

**Why**: In a multi-team environment, the staging layer is owned by the data engineering team; gold is owned by analytics. A change to staging should not break gold without coordination. Groups make ownership explicit.

**Syntax** — in `dbt_project.yml`:

```yaml
groups:
  - name: data_engineering
    owner:
      name: Data Engineering
  - name: analytics
    owner:
      name: Analytics Team
```

In model schema files:
```yaml
models:
  - name: stg_users
    config:
      group: data_engineering
  - name: gold_user_purchases
    config:
      group: analytics
      access: public   # other groups can ref() this model
```

**Effort**: ~1 hour. Config changes only.

---

## Phase 6: Visualization

**Goal**: Make the gold layer visible — dashboards that tell a story from the transformed data.

### 6.1 — Metabase (POC BI layer)

**What**: Open-source BI tool added as a single Docker container. Connects directly to the gold schema in PostgreSQL. Provides interactive dashboards, charts, and ad-hoc SQL exploration.

**Why Metabase**: Lowest setup effort (1 container), highest demo impact, largest community (~40k+ GitHub stars, AGPL license). Auto-discovers PostgreSQL tables. Non-technical users can explore data without writing SQL. Completes the full modern data stack: Airbyte (ingest) → dbt (transform) → Airflow (orchestrate) → Metabase (visualize).

**Setup**: Already wired in `docker-compose.yaml`. Metabase uses the existing PostgreSQL instance for its own app state (database `metabase`). On first launch, complete the setup wizard at `http://localhost:54892` and add the data warehouse connection:

- **Database type**: PostgreSQL
- **Host**: `postgres` (Docker network hostname)
- **Port**: `5432`
- **Database**: `airbyte_raw`
- **Username**: `dbt_user` / **Password**: `dbt_password`
- **Schema filter**: Select `gold` (optionally `marts` for dimension tables)

**Dashboard ideas** (from `gold_user_purchases`):
- Top spenders by total_spent (bar chart)
- Return rate distribution (histogram)
- Revenue by country_code (pie/map)
- Avg purchase value vs return rate (scatter)
- Purchase activity timeline (line chart using first/last_purchase_at)

**Effort**: Done (infrastructure). ~30 min for initial dashboard creation.

### 6.2 — Lightdash (dbt-native BI) — BACKLOG

**What**: Graduation path from Metabase when metrics governance becomes important. Lightdash reads dbt `schema.yml` directly — dimensions, metrics, and joins defined in dbt become Lightdash explores automatically, eliminating metric drift between the transformation and visualization layers.

**Why not now**: Requires 3 Docker services (app + PostgreSQL + Redis), deeper dbt YAML setup (metrics definitions in schema files), and solves a problem (metric drift) that doesn't exist at POC scale with one gold model. Lightdash is the right tool when the team grows and multiple people define metrics.

**When to migrate**: When any of these signals appear:
- Multiple analysts defining metrics independently (drift risk)
- Business logic duplicated between dbt and Metabase questions
- Need for a governed semantic layer (single source of truth for "what is revenue?")

**Effort**: ~3 hours (Docker setup + dbt YAML metric definitions + initial explores).

---

## Implementation Order

```
Phase 1 (Testing Depth)         ← Foundation — do first
│
├─ 1.1  dbt build switch           ✅ DONE   [Airflow DAG simplified]
├─ 1.2  Unit tests                  ✅ DONE   [4 unit tests on gold model]
├─ 1.3  Source freshness            ⏳ TODO   [deferred — requires Airbyte mode]
└─ 1.4  Model contracts             ✅ DONE   [enforced on marts + gold, with precision]
                                    ─────
                                    ~1 hr remaining (1.3 only)

Versioning (added)              ← Pairs with contracts
│
└─  Model versioning                ✅ DONE   [all mart/gold models at v1]

Phase 2 (Observability)         ← Highest demo impact
│
└─ 2.1  Elementary                  ⏳ TODO   [package + CLI + Docker]
                                    ─────
                                    ~3 hr

Phase 3 (SQL Quality Gates)     ← Team hygiene
│
├─ 3.1  SQLFluff                    ⏳ TODO   [config + initial fix]
└─ 3.2  Pre-commit hooks            ⏳ TODO   [config only]
                                    ─────
                                    ~1.5 hr

Phase 4 (CI/CD)                 ← Team readiness
│
├─ 4.1  GitHub Actions slim CI      ⏳ TODO   [workflow + CI profile]
└─ 4.2  dbt compile check           ⏳ TODO   [1 CI step]
                                    ─────
                                    ~3.5 hr

Phase 5 (Governance)            ← Multi-team maturity
│
├─ 5.1  Exposures                   ✅ DONE   [3 exposures declared]
└─ 5.2  Groups & access             ⏳ TODO   [config only]
                                    ─────
                                    ~1 hr remaining (5.2 only)

Phase 6 (Visualization)         ← Data storytelling
│
├─ 6.1  Metabase (POC BI)          ✅ DONE   [docker-compose + gold schema]
└─ 6.2  Lightdash (dbt-native BI)  📋 BACKLOG [graduation path when metrics governance matters]
                                    ─────
                                    6.2: ~3 hr (3 Docker services + dbt YAML metrics)

Total remaining effort: ~10 hours (excl. backlog)
```

---

## Dependencies Between Phases

```
Phase 1 ──→ Phase 2 (Elementary captures test results from Phase 1)
Phase 1 ──→ Phase 4 (CI runs dbt build from Phase 1)
Phase 3 ──→ Phase 4 (CI includes SQLFluff lint from Phase 3)

Phase 2 and Phase 5 are independent — can be done in any order.
Phase 3 is independent — can be done anytime.
Phase 6 is independent — Metabase queries gold tables directly.
Phase 6.2 (Lightdash) depends on Phase 6.1 adoption learnings.
```

---

## What This Does NOT Cover

These are outside the scope of this roadmap but worth noting for future reference:

| Topic | Why excluded | When to revisit |
|-------|-------------|-----------------|
| Cloud warehouse migration (Snowflake/BigQuery) | Architecture change, not maturity layer | When data volume exceeds PostgreSQL capacity |
| Airbyte Cloud / managed connectors | Infrastructure change | When self-hosted maintenance becomes a burden |
| dbt Cloud / dbt Mesh | Platform change | When multi-project governance is needed |
| Airflow → Dagster/Prefect migration | Orchestrator swap | When Airflow operational overhead becomes significant |
| `cosmos` (Airflow dbt provider) | Replaces `docker exec` pattern with native Airflow operators | When per-model Airflow visibility is required |
| Data contracts across teams (Soda, Monte Carlo) | Enterprise-grade observability | When Elementary's scope is insufficient |
| Lightdash (dbt-native BI) | Metabase sufficient at POC scale | When metric drift between dbt and BI becomes a problem (see Phase 6.2) |
