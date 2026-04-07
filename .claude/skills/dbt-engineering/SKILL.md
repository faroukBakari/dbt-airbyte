---
name: dbt-engineering
description: dbt platform engineering methodology — project structure, SQL style, naming conventions, testing coverage, materializations, governance, CI/CD, performance tuning, refactoring, and anti-patterns. Load when building dbt models, reviewing dbt PRs, creating dbt tests, choosing materializations, writing dbt SQL, organizing dbt YAML, or evolving dbt projects.
user-invocable: false
---

# dbt Engineering — Production Methodology

Opinionated methodology for building and maintaining dbt projects. Synthesized from dbt Labs guides, Coalesce 2024-2025, and community production experience.

## S1 Project Structure

### Three-Layer Architecture

```
models/
  staging/<source>/        stg_<source>__<entity>     view
  intermediate/            int_<logic>__<entity>       ephemeral|view
  marts/<domain>/          fct_<event> / dim_<entity>  table
```

**Rules:**
- Staging: 1:1 with source. Rename, cast, deduplicate. No joins. No aggregations.
- Intermediate: Multi-source joins, complex transforms. Optional — skip if <10 marts.
- Marts: Business entities grouped by domain. Fact + dimension tables.
- `source()` only in staging. `ref()` everywhere else. Never hardcode table names.
- Staging never refs staging. Marts never ref staging directly (go through intermediate).

### File Organization

| File | Location | Convention |
|------|----------|------------|
| Model SQL | `models/<layer>/<domain>/` | One concern per file. Max ~300 lines. |
| Schema YAML | Same directory as models | `_<domain>__models.yml` (underscore prefix) |
| Source YAML | `models/staging/<source>/` | `_<source>__sources.yml` |
| Tests (singular) | `tests/` | `<assertion_name>.sql` |
| Macros | `macros/` | Namespaced: `grant__`, `audit__`, `dq__` |
| Seeds | `seeds/` | Lookup tables only. Max 10K rows / 10MB. |

### Folder-Level Config (dbt_project.yml)

```yaml
models:
  my_project:
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral
    marts:
      +materialized: table
      +contract: {enforced: true}
```

Set defaults at folder level. Override per-model only when necessary.

## S2 SQL Craft

### CTE Pattern: Import-Logic-Final

Every model follows this structure:

```sql
with

source as (
    select * from {{ source('stripe', 'payments') }}
),

renamed as (
    select
        id as payment_id,
        order_id,
        (amount / 100.0)::numeric(10,2) as amount,
        status as payment_status,
        is_refunded,
        created_at
    from source
)

select * from renamed
```

**CTE naming:** After the entity they represent (`payments`, `orders`), not
`cte_1`. Logic CTEs use verbs: `aggregated_orders`, `deduplicated`.

### Style Conventions

| Convention | Standard | Rationale |
|-----------|----------|-----------|
| Keywords | lowercase (`select`, `from`) | dbt Labs / Brooklyn Data consensus |
| Commas | Trailing (last column gets comma) | Easy to comment/uncomment lines |
| Aliasing | Always use `AS` | Explicit > implicit |
| `SELECT *` | Only in staging import CTEs | Breaks contracts, hides schema changes |
| Column order | IDs → strings → numerics → booleans → dates → timestamps | Consistent scanning |
| `GROUP BY` | Column names, not numbers | Numbers break on reorder |
| Line length | Max 120 chars | Readability |
| Joins | Explicit `LEFT JOIN ... ON` | Never implicit comma-joins |

### Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Primary key | `<entity>_id` | `order_id` (never bare `id`) |
| Foreign key | `<referenced_entity>_id` | `customer_id` in orders |
| Boolean | `is_<state>` or `has_<attr>` | `is_active`, `has_subscription` |
| Date | `<event>_date` | `order_date`, `created_date` |
| Timestamp | `<event>_at` | `created_at`, `updated_at` (UTC) |
| Amount | `<noun>_amount`, numeric type | `order_amount` (never float) |
| All names | `snake_case` | No camelCase, no abbreviations |

### ref/source Hygiene

- `source()`: ONLY in staging models. Declares external data boundary.
- `ref()`: ALL model-to-model references. Enables DAG tracking, slim CI.
- Cross-project: `{{ ref('project_name', 'model_name') }}` (dbt Mesh).
- Never: `SELECT * FROM raw.schema.table` — invisible to DAG.

## S3 Testing Strategy

### Coverage Matrix

| Column Type | Required Tests | Layer |
|------------|----------------|-------|
| Primary key | `unique` + `not_null` | All |
| Foreign key | `relationships` + `not_null` | Marts+ |
| Enum/status | `accepted_values` | All |
| Timestamp | `not_null` + `expression_is_true: <= current_timestamp` | Marts+ |
| Amount | `not_null` + `expression_is_true: >= 0` | Marts+ |
| Boolean | `accepted_values: [true, false]` | If nullable |

### Test by Layer

| Layer | Test Focus | Severity |
|-------|-----------|----------|
| **Staging** | Source-level: PK unique+not_null, freshness | `error` |
| **Intermediate** | Light: PK only (logic tested via unit tests) | `warn` |
| **Marts** | Full: PKs, FKs, enums, amounts, business rules | `error` |
| **Gold** | Full + contracts + data quality (Elementary) | `error` |

### Unit Tests (dbt 1.8+)

Test business logic in isolation, no database needed:

```yaml
unit_tests:
  - name: test_return_rate_zero_returns
    model: gold_user_purchases
    given:
      - input: ref('dim_users')
        rows: [{user_id: 1, total_purchases: 10, total_returns: 0, total_spent: 500.00}]
    expect:
      rows: [{user_id: 1, return_rate_pct: 0.0}]
```

**What to unit test:** Business formulas, edge cases (NULL, zero, negative, division by zero, empty sets), conditional logic (CASE statements). Execution order: unit tests → models → data tests. Failure blocks materialization.

### Test Severity Strategy

- `severity: error` — blocks downstream in `dbt build`. Use for: PKs, FKs, contracts, critical business rules.
- `severity: warn` — logs only. Use for: data quality observations, legacy models, non-critical checks.
- `store_failures: true` — saves failing rows for debugging. Use on marts+.
- `warn_if` / `error_if` — threshold-based: `error_if: ">10"` allows up to 10 failures.

### Test Anti-Patterns

- Testing every column for `not_null` (only required columns)
- Testing staging models (test sources instead — staging is pass-through)
- Tests that never fail (no signal, just noise)
- Hardcoded thresholds that break with data growth (use anomaly detection)
- Over-testing: if contracts enforce schema, don't duplicate with generic tests

## S4 Materializations

### Decision Tree

```
Is it a staging model?                    → view
Is it lightweight, <4 downstream refs?    → view
Is it an intermediate CTE used 1-2x?     → ephemeral
Is it a mart/gold consumed by BI?         → table
Is it a large fact table (>100K rows)?    → incremental
Does the warehouse manage refresh?        → materialized_view
```

### Incremental Strategy Selection

| Strategy | Use When | Warehouse |
|----------|----------|-----------|
| `merge` | Upserts with unique_key (default) | Snowflake, BigQuery, Databricks |
| `delete+insert` | When merge unavailable | Postgres, Redshift |
| `microbatch` | Time-series, large tables (dbt 1.9+) | All |
| `append` | No dedup needed | All |
| `insert_overwrite` | Partition replacement | Databricks |

### Microbatch (dbt 1.9+ — Preferred for Time-Series)

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='created_at',
    batch_size='day',
    lookback=3,
    unique_key='event_id'
) }}
select * from {{ source('events', 'raw_events') }}
```

No `is_incremental()` needed. Auto-filters by time. `lookback=3`
reprocesses 3 prior batches for late-arriving data.

### Materialization Anti-Patterns

- Table everywhere (wastes storage/compute)
- Ephemeral chains >4 deep (impossible to debug)
- No `unique_key` on incremental merge (creates duplicates)
- `SELECT *` in incremental (defeats incremental purpose)
- View cascade: slow view → slow view → slow view (break with table)

## S5 YAML & Documentation

### Schema File Structure

```yaml
# models/marts/finance/_finance__models.yml
version: 2

models:
  - name: fct_orders
    description: Order facts with totals and status tracking
    config:
      contract: {enforced: true}
      tags: ['marts', 'finance']
      meta: {owner: finance_team, sla_hours: 4}
    columns:
      - name: order_id
        description: Primary key — unique order identifier
        data_type: bigint
        data_tests: [unique, not_null]
      - name: customer_id
        description: FK to dim_customers
        data_type: bigint
        data_tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
      - name: order_total
        description: Total including tax and shipping (USD)
        data_type: numeric(10,2)
        data_tests: [not_null]
```

### Documentation Standards

- **Every column** gets a description. PKs and FKs state their role explicitly.
- **Enums**: List valid values in description.
- **Nullable columns**: Explain when NULL occurs.
- **Amounts**: State currency, precision, calculation source.
- **Timestamps**: State timezone (UTC assumed unless noted).
- **Doc blocks**: Use for reusable descriptions shared across models.

### Source Freshness

```yaml
sources:
  - name: raw_data
    loaded_at_field: _airbyte_emitted_at
    freshness:
      warn_after: {count: 12, period: hour}
      error_after: {count: 24, period: hour}
    tables:
      - name: users
      - name: orders
```

Run `dbt source freshness` before `dbt build` in orchestration.

### Seeds: When Appropriate

- Lookup/reference tables: country codes, status mappings, fiscal calendars
- Max 10K rows / 10MB. Beyond that → use EL tool + source()
- Never for: raw data, frequently-changing data, PII
- Always define `column_types` in seeds.yml (prevent type inference issues)

## S6 Governance

### Contracts (Marts and Gold Only)

```yaml
config:
  contract: {enforced: true}
columns:
  - name: user_id
    data_type: bigint
    constraints: [{type: not_null}]
```

Contracts enforce schema at build time. Column type mismatch → build failure.
Apply to materialized tables only (not views/ephemeral).

### Model Versioning (Breaking Changes)

```yaml
models:
  - name: dim_users
    latest_version: 2
    versions:
      - v: 1
        deprecation_date: "2025-06-01"
      - v: 2
        columns:
          - include: all
          - name: new_column
```

Downstream: `{{ ref('dim_users', v=2) }}`. Unversioned refs get latest.
Migration window: 30-90 days between versions.

### Access Control

| Level | Scope | Use |
|-------|-------|-----|
| `public` | Cross-project | Stable APIs for downstream teams |
| `protected` | Same project (default) | Internal models |
| `private` | Same group only | Implementation details |

### Exposures (Downstream Consumers)

```yaml
exposures:
  - name: executive_dashboard
    type: dashboard
    depends_on: [ref('gold_user_purchases')]
    owner: {name: Analytics, email: analytics@co.com}
```

Declare dashboards, reports, ML pipelines. Shows impact in lineage graph.

## S7 CI/CD

### Pipeline Pattern

```
PR → SQLFluff lint → dbt parse (no DB) → dbt build --select state:modified+ --defer
```

### Slim CI (Required for Production)

```bash
dbt build \
  --select state:modified+ \
  --defer \
  --state ./prod-manifest/ \
  --target ci
```

Requires: `manifest.json` from last successful prod run. Only builds changed models + downstream dependents. 60%+ faster than full builds.

### Pre-commit Hooks (Minimum)

- SQLFluff lint (SQL style)
- check-yaml (YAML validity)
- trailing-whitespace + end-of-file-fixer

Optional: dbt-checkpoint (`model-has-tests`, `model-has-properties`).

**Rule**: 2-3 fast hooks locally. Heavy validation in CI. Prevents `--no-verify` abuse.

## S8 Macros & Jinja

### Macros: When and How

Extract when: pattern in 2+ models, warehouse-specific SQL, independently testable logic, or cross-project reuse.
- Namespace: `grant__`, `audit__`, `dq__`, `util__`. Required args first, optional last.
- Always return compiled SQL strings. Test via `dbt run-operation` or unit test wrapper models.

### Key Built-in Macros to Override

- `generate_schema_name()` — custom schema routing (dev prefix, prod clean)
- `generate_alias_name()` — table naming with versioning
- Grant permissions via `on-run-end` hooks

### Jinja Rules of Thumb

- Don't Jinja-ify trivial SQL — justify added complexity. Debug via `dbt compile --select my_model`.
- `{% set %}` for local model state; `{{ var() }}` for CLI/project injection; `{{ env_var() }}` for secrets — never hardcode credentials.
- Whitespace control (`{%- -%}`) only if causing SQL syntax errors. Readability wins.

### Snapshots

- **Timestamp** (preferred): needs reliable `updated_at`. **Check**: specify columns — never `check_cols: all`.
- YAML-based (dbt 1.9+), not SQL blocks. Test: `dbt_scd_id` not_null, `dbt_valid_from` not_null.

## S9 Performance

### Optimization Checklist

1. **Incremental filter**: Always filter new data in incremental models
2. **Table breaks**: Insert table materialization every 4+ chained views
3. **Incremental predicates**: Limit scan range on both source and target
4. **Warehouse features**: Clustering (Snowflake/BQ), sort keys (Redshift), Z-order (Databricks)
5. **Partial parsing**: Keep `target/` between runs (auto in 1.4+). **Slim CI**: `state:modified+` — never full-build.

### Finding Slow Models

```bash
cat target/run_results.json | jq '.results | sort_by(.execution_time) | reverse | .[0:5] | .[] | {model: .unique_id, time: .execution_time}'
```

### When to Add Intermediate Tables

- Query takes >30s and feeds 3+ downstream models
- Same CTE logic duplicated across multiple marts
- View cascade causes BI query timeouts

## S10 Maintenance & Refactoring

### Safe Model Rename

1. Add `alias` to old model; create new model file with new name
3. Update downstream refs over migration window (30-90 days)
4. Set `deprecation_date` on old version — dbt warns on deprecated refs
5. Remove old model after migration window

### Materialization Migration (view → incremental)

1. Create new model with incremental config; backfill with `dbt run --full-refresh --select new_model`
2. Validate with `dbt-audit-helper` (compare row counts, column values); swap downstream refs
3. Remove old model

### Schema Change Handling (Incremental)

| `on_schema_change` | Behavior | Use When |
|--------------------|----------|----------|
| `ignore` (default) | New columns silently dropped | Never (dangerous) |
| `append_new_columns` | New columns added, removed columns kept | Staging |
| `sync_all_columns` | Schema fully synced | Marts (with contracts) |
| `fail` | Build fails on schema change | Gold (maximum safety) |

### Code Review Checklist

- [ ] Breaking changes? (column removal, rename, type change)
- [ ] Materialization appropriate for model's role?
- [ ] Tests on PKs, FKs, and business-critical columns?
- [ ] Contracts on downstream-facing models?
- [ ] `source()` only in staging, `ref()` everywhere else?
- [ ] No `SELECT *` in marts/gold?
- [ ] Column names follow conventions (snake_case, `_id`, `_at`, `is_`)?
- [ ] Description on model and key columns?
- [ ] Downstream impact considered? (check exposures)

### Scaling Signals

| Signal | Action |
|--------|--------|
| Parse time >60s | Consider splitting into multiple projects (dbt Mesh) |
| >500 models | Evaluate project boundaries by domain |
| >5 teams editing same project | Groups + access control minimum; Mesh if cross-team refs |
| CI builds >15min | Slim CI mandatory; add intermediate table breaks |

## S11 Anti-Pattern Catalog

| Anti-Pattern | Symptom | Fix |
|-------------|---------|-----|
| Flat folder structure | Parse blowup, unclear ownership | Three-layer structure |
| `source()` outside staging | Hidden dependencies, broken freshness | source() only in staging |
| `SELECT *` in marts | Schema drift, broken contracts | Explicit column list |
| No `unique_key` on incremental | Duplicate rows | Always set unique_key |
| Ephemeral chains >4 deep | Undebugable queries | Break with view/table |
| Seeds for raw data | Performance cliff | Use EL tool + source() |
| Table materialization everywhere | Wasted storage/compute | View for staging, table for marts |
| `severity: error` on unstable models | Alert fatigue | Warn for legacy, error for new |
| Full builds in CI | Slow, expensive | Slim CI with `state:modified+` |
| Hardcoded quality thresholds | Break with growth | Anomaly detection (Elementary) |
| No source freshness | Silent stale data | `dbt source freshness` before build |
| Testing staging models | Wasted effort | Test sources instead |
| `GROUP BY 1, 2, 3` | Breaks on column reorder | Group by column names |
| Implicit joins (comma) | Wrong cardinality, silent bugs | Explicit JOIN ... ON |
| Bare `id` column | Ambiguous across joins | `<entity>_id` always |
| Float for money | Precision loss | `numeric(10,2)` |
| Jinja spaghetti | Unreadable, untestable | Extract macros, keep SQL simple |
| `on_schema_change: ignore` | Silent column drops | `append_new_columns` minimum |
| No contracts on shared models | Silent breaking changes | Enforce contracts on marts+ |
| Manual metric definitions in BI | Metric drift | Define in dbt YAML or Semantic Layer |

## S12 Packages (Essential)

| Package | Purpose | Required? |
|---------|---------|-----------|
| `dbt-utils` | SQL generators, cross-db functions | Yes |
| `dbt-expectations` | 62+ data quality tests | Recommended |
| `elementary` | Observability, anomaly detection | Recommended |
| `dbt-codegen` | Boilerplate YAML generation | Nice-to-have |
| `dbt-audit-helper` | Migration validation (row/column compare) | For refactoring |
| `dbt-project-evaluator` | Automated best-practice audit | For maturity |
