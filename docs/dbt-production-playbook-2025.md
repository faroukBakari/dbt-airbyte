# dbt Production Playbook (2025)

> Advanced patterns for maintaining, refactoring, and evolving dbt projects in production.
> Synthesized from Coalesce 2024-2025, dbt Labs docs, Discourse discussions, and community experience.
> Supplements: `docs/dbt-state-of-the-art-2025.md` (foundational guidance).

---

## 1. Refactoring Patterns — Safe Model Changes

### The Three Refactoring Scenarios

| Scenario | Pattern | Approach |
|----------|---------|----------|
| **Rename a model** | `fct_orders` → `dim_orders` | Use `alias` + deprecation period |
| **Split a complex model** | 200-line CTE chain | Extract intermediate models, establish new references |
| **Migrate materialization** | view → incremental | Create new model, run audit, coordinate cutover |

### Safe Rename: Alias + Deprecation

**Step 1: Add alias to old model, set deprecation date**
```yaml
models:
  - name: fct_orders  # old model file name stays same
    config:
      alias: dim_orders  # new table name in warehouse
    columns:
      - name: order_id
        constraints:
          - type: not_null
    versions:
      - v: 1
        deprecation_date: "2025-06-30"
```

**Step 2: Create new model with new name**
```sql
-- models/marts/dim_orders.sql
-- This replaces fct_orders; same logic, new name
select * from {{ ref('fct_orders', v=1) }}
```

**Step 3: Downstream migration**
- Update refs: `{{ ref('fct_orders') }}` → `{{ ref('dim_orders') }}`
- dbt will warn on deprecated refs automatically
- Migration window (30-90 days) allows parallel operation

**Why this works**:
- Old table name (`dim_orders`) exists during transition
- Old model version still available for late consumers
- dbt tracks lineage through deprecation
- No data loss, no surprise breakages

### Safe Materialization Swap: view → incremental

**Anti-pattern**: Simply changing config from `materialized: view` to `materialized: incremental` will fail on first run.

**Correct approach**:

**Step 1: Create the new incremental model alongside the old one**
```sql
-- models/marts/fct_orders_incremental.sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    on_schema_change='sync_all_columns'
) }}

select * from {{ ref('fct_orders') }}  -- ref the view version
where 1=1
{% if execute and execute_context['is_incremental'] %}
  and updated_at > (select max(updated_at) from {{ this }})
{% endif %}
```

**Step 2: Run full refresh to establish baseline**
```bash
dbt run -s fct_orders_incremental --full-refresh
```

**Step 3: Audit both tables match**
```sql
{{ audit_helper.compare_relations(
    a_relation=source('prod', 'fct_orders'),
    b_relation=ref('fct_orders_incremental'),
    primary_key=['order_id']
) }}
```

**Step 4: Switch downstream refs, deprecate old model**
```yaml
models:
  - name: fct_orders
    versions:
      - v: 1
        deprecation_date: "2025-06-30"
```

### Splitting a Large Model

**Symptom**: A single model has 8+ CTEs, >200 lines, logic spans 3+ domains.

**Safe split**:
1. **Extract first CTE into intermediate model** — `int_orders__base`
2. **Test independently** — verify base model produces same rows as original CTE
3. **Update parent to ref intermediate** — parent model now: `with base as ({{ ref('int_orders__base') }})`
4. **Verify lineage** — dbt ls -s int_orders__base+ (should see same downstream as before)
5. **Repeat** — extract next CTE after audit passes

**Key**: Audit after each extraction. One model split per PR. Never split multiple CTEs simultaneously.

---

## 2. Deprecation Workflows — Breaking Changes Without Breaking Users

### Model Versioning Timeline

**dbt 1.5+**: Model versioning + deprecation_date support.

**Pattern: 90-day migration window**

```yaml
models:
  - name: dim_customers
    latest_version: 2
    versions:
      - v: 1
        deprecation_date: "2025-03-31"  # WARNING: 90 days out
        columns:
          - include: all
            exclude: [legacy_field]

      - v: 2
        columns:
          - include: all
            exclude: [removed_field]
```

**What consumers see**:
- Day 0 (Jan 1): dbt warns `ref('dim_customers')` defaults to v=2, v=1 deprecated (warning)
- Day 1-89: Consumers can stay on v=1 with `ref('dim_customers', v=1)` or upgrade to v=2
- Day 90 (Mar 31): v=1 removed. Unversioned refs must upgrade.

### Communication Strategy

**1. Announce breaking change early** (45 days before deprecation_date)
```
Slack announcement:
"Attention @data-users: dim_customers will remove field legacy_field on March 31.
If you reference this model, please review: [link to PR + changelog]
No action needed if you're on the latest version already.
Questions? Reply in #data-eng-updates"
```

**2. Expose version info in lineage**
- dbt Cloud shows deprecation_date in model docs
- dbt CLI warns on parse: "dim_customers v=1 deprecated as of 2025-03-31"

**3. Monitor downstream references**
```bash
# Find all unversioned refs to this model
dbt ls -s dim_customers+ --resource-type model
```

### When NOT to Version

- **Small models** (<100 rows of SQL): Just rename with alias
- **Internal staging models**: No versioning needed (internal consumers only)
- **Rapidly changing models**: Versioning adds maintenance; defer until stable

---

## 3. Technical Debt Management — Cleanup at Scale

### dbt Project Evaluator: Automated Best-Practice Audit

**Install and run**:
```bash
dbt deps  # Brings in dbt-project-evaluator package
dbt build  # Runs evaluator tests + your own
```

**What it finds**:
| Check | Violation | Fix |
|-------|-----------|-----|
| **Model coverage** | Models without tests | Add not_null, unique on PKs |
| **Documentation** | Undocumented models | Run dbt-osmosis or dbt-codegen |
| **Orphaned models** | No downstream refs, no exposures | Deprecate or add lineage |
| **Source refs** | Staging models ref multiple sources | Consolidate in staging layer |
| **Naming violations** | `fact_` models that are dimensions | Rename to `dim_` prefix |
| **Nested staging** | Staging models inside marts folder | Reorganize folder structure |

**Typical output**:
```
Found 47 violations:
- 12 models without tests
- 8 undocumented models
- 3 models with no downstream refs
- 2 hard-coded source references
```

**Cleanup strategy**:
1. Run evaluator in CI (non-blocking) to track trends
2. Prioritize violations by impact:
   - **High**: Undocumented high-traffic models, orphaned tables eating storage
   - **Medium**: Low-traffic undocumented models, naming inconsistencies
   - **Low**: Optional test additions, documentation polish

3. Set quarterly "debt reduction" sprints — allocate 20% of capacity

### Finding and Removing Unused Models

**Query: Models with 0 downstream refs and 0 exposures**
```sql
-- Run in dbt Cloud or against manifest.json
select model, created_date from dbt_models
where model not in (
  select distinct downstream from dbt_dependencies
) and model not in (
  select distinct model from dbt_exposures
)
order by created_date;
```

**Decision framework**:
- **Zero refs + >6 months old** → Deprecate + remove (check git blame for owner context first)
- **Zero refs + <6 months old** → Keep (new models may not have consumers yet)
- **Historical archive models** → Tag `meta: {deprecated: true}` but keep in repo for lineage

---

## 4. Schema Migration — Handling Column Changes Safely

### on_schema_change Options: When to Use Each

| Setting | Behavior | Use Case |
|---------|----------|----------|
| `fail` | Refuse to run if schema mismatch | Strict governance, catch surprises (default, safe) |
| `ignore` | Don't touch schema, fail silently | Not recommended; hides real issues |
| `append_new_columns` | Add new columns, keep old ones | **Use for staging**: upstream adds fields |
| `sync_all_columns` | Add new + remove missing columns | **Use for marts**: schema must match exactly |

### Safe Pattern: Staging Layer with append_new_columns

**Staging models**: Upstream data adds columns → append them automatically

```yaml
models:
  - name: stg_customers
    config:
      materialized: view
      on_schema_change: append_new_columns
    description: "1:1 with raw.customers, auto-appends new columns"
```

**Behavior**:
- Day 0: Raw table has columns `[id, name, email]`
- Day 15: Raw adds column `phone_number`
- Day 16: stg_customers auto-appends `phone_number` (values = NULL for historical rows)
- Day 17: Downstream models inherit the new column

**Why this is safe**:
- New columns are nullable
- Downstream can ignore them until ready
- No full refreshes needed
- Single source of truth (raw data) drives schema evolution

### Dangerous Pattern: Changing Column Logic in Incrementals

**Problem**:
```sql
-- First run: created column as cast(raw_created as date)
{{ config(
    materialized='incremental',
    unique_key='id',
    on_schema_change='append_new_columns'
) }}

select
  id,
  cast(raw_created as date) as created_date  -- CAREFUL: logic change here
from raw.orders
```

**Solution**:
1. **Plan schema changes alongside logic changes**
   - Add new column (`created_date_fixed`)
   - Keep old column (`created_date`) for now
   - Let downstream migrate to new column

2. **Full refresh incremental quarterly** (separate job)
   ```bash
   dbt run -s fct_orders --full-refresh
   ```

3. **Use audit_helper to validate**
   ```sql
   dbt test -s fct_orders.compare_schemas
   ```

### dbt-utils: safe-model-changes Pattern

Use `dbt-utils.get_query_results_as_dict()` to introspect schema before modifying:

```sql
{% set column_info = run_query(
    "describe table " ~ target_relation,
    execute=execute
) %}

{% if execute %}
  {% for row in column_info %}
    -- Process each column safely
  {% endfor %}
{% endif %}
```

---

## 5. Performance Debugging — Finding and Fixing Slow Models

### Step 1: Identify Bottlenecks Using run_results.json

**After a dbt run, parse the artifact**:
```bash
# Get top 10 slowest models
python3 << 'EOF'
import json
from operator import itemgetter

with open('target/run_results.json') as f:
    results = json.load(f)

timings = []
for result in results['results']:
    if result['status'] in ['success', 'error']:
        timings.append({
            'model': result['unique_id'].split('.')[-1],
            'execution_time': result['execution_time'],
            'compile_time': result.get('compile_time', 0)
        })

for item in sorted(timings, key=itemgetter('execution_time'), reverse=True)[:10]:
    print(f"{item['model']}: {item['execution_time']:.2f}s exec, {item['compile_time']:.2f}s compile")
EOF
```

**Rule of thumb**:
- `execution_time > 60s` — model is a bottleneck
- `compile_time > 10s` — investigate macros / Jinja complexity

### Step 2: Check Query Profile in Warehouse

**Snowflake**:
```sql
select
  query_id,
  query_text,
  execution_time,
  compilation_time,
  queued_provision_time
from snowflake.account_usage.query_history
where user_name = 'dbt_service_account'
  and start_time > current_timestamp - interval '1 hour'
order by execution_time desc
limit 10;
```

**Key metrics**:
- **Queued time**: Warehouse too small
- **Compilation time**: Complex joins, many subqueries
- **Execution time**: Data volume, missing indexes, broadcast failures

### Step 3: Common Bottleneck Patterns and Fixes

| Pattern | Symptom | Fix |
|---------|---------|-----|
| **Cascading views** | 4+ chained views, slow execution | Break chain with table at layer 3 |
| **SELECT \*** | Schema explosion, wide passes | Explicit column lists |
| **Unfiltered joins** | Cartesian products, OOM | Add filter predicates, check join logic |
| **Multiple passes on same table** | Repeated scans in CTEs | Materialize as ephemeral or intermediate |
| **Missing partition pruning** | Full table scans on large tables | Add `where created_date > ...` for incrementals |

### Step 4: When to Add Intermediate Tables

**Decision tree**:
```
Is the model slow (>60s)?
├─ YES:  Does it have 4+ CTEs? → Create int_* intermediate
│        Does it have heavy joins? → Extract join step to int_*
│        Does it scan 100M+ rows? → Consider incremental + intermediate
└─ NO:   Leave as is
```

**Example: Breaking a slow mart**
```sql
-- BEFORE: Single 120s query
{{ config(materialized='table') }}
with base as (...),
     customers as (...),
     orders as (...),
     enrichment as (...),
     final as (...)
select * from final

-- AFTER: Two materialized models
-- Step 1: Intermediate (30s)
{{ config(materialized='table') }}
with base as (...),
     customers as (...)
select * from customers join base

-- Step 2: Mart (15s)
{{ config(materialized='table') }}
select * from {{ ref('int_orders_customers') }}
join {{ ref('int_enrichment') }}
```

**Total time**: 120s → 30s + 15s + 10s (mart) = 55s saved.

---

## 6. Dependency Management — Handling Version Upgrades

### dbt-core Upgrade Path (1.7 → 1.8 → 1.9 → 1.10 → 1.11)

**Breaking changes by version**:

| Version | Breaking Changes | Migration |
|---------|------------------|-----------|
| **1.8** | Adapters decouple from dbt-core; must install `dbt-core` + `dbt-<adapter>` separately | `pip install dbt-core==1.8.0 dbt-snowflake==1.9.0` |
| **1.9** | `{{ target.account }}` replaces underscores with dashes (Snowflake only); microbatch replaces manual incremental | Update Snowflake account refs; test incrementals |
| **1.10** | YAML deprecation warnings enabled by default; dbt-autofix tool released | Run `dbt-autofix` to auto-migrate deprecated configs |
| **1.11** | Redshift: skip unnecessary COMMIT statements; Redshift/PyHive connection retry options | No action for most users |

### Safe Upgrade Checklist

1. **Test in dev environment first**
   ```bash
   pip install dbt-core==X.Y.Z dbt-<adapter>==X.Y.Z
   dbt parse  # Catch parse errors
   dbt build --select state:modified+  # Quick smoke test
   ```

2. **Run deprecation audits**
   ```bash
   dbt-autofix scan --check-all  # List deprecated configs
   dbt-autofix apply --behavior-change  # Auto-fix (create PR first!)
   ```

3. **Test breaking changes specific to your adapter**
   - **Snowflake 1.9+**: Search for `{{ target.account }}` in your code; update to use dashes
   - **Incremental models**: Verify `on_schema_change` behavior unchanged

4. **Update packages in lockfile**
   ```bash
   rm packages.lock.yml
   dbt deps
   dbt build  # Re-run with new packages
   ```

5. **Merge and monitor production** — upgrade in off-hours with rollback plan

### Adapter Compatibility

**dbt-adapters interface** (v1.8+): Manages compatibility between dbt-core and adapter versions.

**Safe versioning**:
```
dbt-core 1.8.0 can work with dbt-snowflake 1.8.0, 1.9.0, 1.10.0, etc.
dbt-core 1.9.0 can work with dbt-snowflake 1.8.0+

But NOT: dbt-core 1.7 with dbt-snowflake 1.9 (interface mismatch)
```

**Check compatibility** before upgrading:
```bash
dbt --version
# Shows:
# dbt core: 1.8.0
# dbt-snowflake: 1.9.2  ← Must be >= same minor as dbt-core for safety
```

---

## 7. Production Incident Patterns — When Things Break

### Common Failure Modes

| Failure | Symptom | Root Cause | Recovery |
|---------|---------|-----------|----------|
| **Stale data** | BI reports show yesterday's data, dbt ran but no new rows | Source freshness check missed; freshness_error was warning not error | Re-run dbt with `dbt source freshness --warn-error` to fail fast |
| **Schema drift** | dbt run fails; "column not found in target"; source added/removed columns | Upstream schema changed; `on_schema_change` not set or set to `fail` | Set `on_schema_change: append_new_columns` on staging, then `dbt run --full-refresh` |
| **Test failure blocks pipeline** | dbt build stops at failing test; downstream models not updated | Test caught real data issue OR flaky test (randomness, timing) | `dbt test --fail-fast` to isolate; review test logic; escalate if data-level |
| **Incremental duplicates** | Row counts double; `unique_key` constraint violated | `unique_key` missing or wrong; dbt merge used but data has duplicates | Backfill: `dbt run --full-refresh` on affected model; review unique_key |

### Incident Response Playbook

**Step 1: Immediate triage (5 min)**
- What failed? (model, test, freshness, or source?)
- Is it blocking downstream consumers?
- Is the data wrong or is the model correct but test is broken?

**Step 2: Determine severity**
- **Critical**: Production tables corrupted, stale data served to BI
- **High**: Pipeline failed, needs manual fix before next run
- **Medium**: Test failure, data is correct but alert fired
- **Low**: Performance degradation, warnings in logs

**Step 3: Rollback vs forward**
- **Rollback** if: Last commit broke production; git revert + dbt run --full-refresh
- **Forward** if: Data source issue (upstream schema, data quality); investigate root cause, fix in dbt, re-run

**Step 4: Post-incident**
- Document root cause in Slack thread (what, why, how fixed, how prevent next time)
- Create ticket for monitoring (e.g., "add anomaly detection for order counts")
- Review dbt_build CI log — why didn't CI catch this?

### Preventing Stale Data: dbt source freshness

**Standard config**:
```yaml
sources:
  - name: raw_data
    tables:
      - name: events
        loaded_at_field: "_airbyte_emitted_at"
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
```

**In orchestration** (Airflow/Dagster):
```bash
dbt source freshness --warn-error  # Exit 1 if any errors
if [ $? -ne 0 ]; then
  echo "Source freshness check failed; aborting dbt build"
  exit 1
fi
dbt build
```

**Why warn-error matters**: Stale source = stale models = wrong dashboards. Fail fast.

### Test Failure Escalation

**When a test fails in production**:

1. **Check if data is actually wrong**
   ```sql
   -- Is the constraint truly violated?
   select count(*) from {{ ref('model') }}
   where pk is null;  -- If count > 0, test is right
   ```

2. **If data is wrong**: Stop the pipeline, investigate source
   ```bash
   dbt test -s model --store-failures
   # Check dbt_test__audit schema for failing rows
   ```

3. **If test is flaky** (passes sometimes):
   - Timing issues (test too slow, gets interrupted)?
   - Randomness (SELECT * without ORDER BY)?
   - Competing processes (multiple dbt runs simultaneously)?
   - Fix: Add `order_by`, increase timeout, serialize dbt runs

### Rollback Strategy

**Blue-green pattern** (recommended for dbt):
```
Production tables: `{schema}_prod`
Staging tables:   `{schema}_dev`

CI builds to dev → Tests run → Prod swap
If prod fails, revert to previous schema snapshot
```

**In dbt**:
```yaml
# dbt_project.yml
models:
  materialized: table
  schema: '{{ "prod" if target.name == "prod" else "dev" }}'
```

**Rollback** (if something breaks):
```bash
# Option 1: Revert last commit + dbt run --full-refresh
git revert HEAD
dbt run --full-refresh --target prod

# Option 2: Time-travel (Snowflake/Databricks)
create or replace table orders as
  select * from orders.clone_of_yesterday();

# Option 3: Use dbt retry to re-run last good state
dbt retry --state ./previous-good-run/
```

---

## 8. Code Review Checklist — What Senior Engineers Look For

### Pre-Review: Self-Review Checklist

Before submitting a PR, ask yourself:

- **Breaking changes?** Does this rename, remove, or change the logic of a public model?
  - If yes: Is deprecation_date set? Are downstream models versioned?

- **Tests added?** For new models: not_null + unique on PK. For existing: unit tests for logic?

- **Materialization choice justified?** Staging=view, marts=table. Why if different?

- **Downstream impact?** Does this change affect 100+ models? Notify team first.

- **Performance?** Added a new join? Checked row counts? Run_results show execution time?

- **Documentation?** New models have descriptions. Existing models have comments on tricky logic.

### Reviewer Checklist

**When reviewing a dbt PR, look for**:

| Check | Good Sign | Red Flag |
|-------|-----------|----------|
| **Scope** | 1-3 models changed | Changes span 5+ domains; mix of refactoring + new features |
| **Tests** | All new columns have tests; critical models have unit tests | No tests added; "will test in prod" |
| **Breaking changes** | Clear deprecation_date; downstream team tagged | Silent breaking change; no communication |
| **Materialization** | Justified in PR description; follows conventions | Random table vs view choice; ephemeral 4+ deep |
| **Naming** | Follows conventions; follows folder structure | Model named by feature, not entity; mixed prefixes |
| **Downstream impact** | Lineage shows expected dependencies; ~3-5 models affected | Lineage shows 50+ affected models; no impact analysis |
| **SQL** | Readable CTEs; partition pruning on large tables | SELECT *; full table scans; missing filters |
| **Diff quality** | Small, focused diffs | 500+ line change; hard to review |

### Impact Assessment Tools

**Recce** (zero-config): Auto-detects modified models + downstream impact
```bash
# After PR commit
recce run
# Shows: changed models, affected downstream, row count diffs
```

**dbt Cloud**: Model Timing + Lineage visualization in UI

**Command-line**:
```bash
# Models changed in this branch
dbt ls -s state:modified --state ./prod-manifest/

# Downstream impact
dbt ls -s state:modified+ --state ./prod-manifest/
```

---

## 9. Project Scaling — Monolith to Mesh (500+ Models)

### When to Split: Maturity Signals

**Stay monolith if**:
- < 500 models
- 1-2 teams
- Parse time < 30 seconds
- Clear ownership (no "who owns this?" confusion)

**Split into Mesh if**:
- \> 500 models AND parse time > 60 seconds
- 3+ teams with unclear ownership boundaries
- Frequent CI/CD conflicts (different teams stepping on each other)
- Hard to add new tests without breaking existing tests

### Monolith-to-Mesh Migration Path

**Phase 1: Prepare (1-2 months)**
1. Run dbt Project Evaluator → identify orphaned / undocumented models
2. Establish clear domain boundaries (finance, marketing, product, etc.)
3. Assign teams to domains
4. Deploy model contracts + access levels on critical models

**Phase 2: Extract first team (1 month)**
1. Pick one team with clear model boundary (e.g., finance domain = 80 models)
2. Create new project: `dbt-finance-core`
3. Copy their 80 models + dependencies
4. Use `dbt-loom` (open-source) or `dbt Mesh` (Cloud) for cross-project refs
5. Run in parallel: old monolith + new project
6. Cut over downstream via alias swap

**Phase 3: Extract remaining teams (parallel)**
- Teams extract simultaneously; orchestrator (Airflow/Dagster) coordinates
- Shared staging layer (common to all teams) remains in central project

**Phase 4: Establish governance**
- Central project: staging models only (shared by all teams)
- Team projects: marts + custom staging
- Central team owns SLAs + data contracts

### dbt Mesh Cross-Project Refs

**Syntax** (dbt 1.5+, dbt Cloud Enterprise or dbt-loom):
```sql
-- finance project: models/fct_transactions.sql
select
  t.transaction_id,
  c.customer_id,
  t.amount
from {{ ref('transactions') }}  -- Local (finance project)
join {{ ref('upstream_project', 'dim_customers') }}  -- External (Mesh)
```

**Governance**:
- Only `public` models can be ref'd across projects
- Contracts enforced at project boundary
- dbt tracks lineage across projects

---

## 10. Advanced Debugging Techniques

### Query Profile Analysis (Snowflake)

**For a slow model, get the query_id from logs**:
```bash
cat logs/dbt.log | grep "fct_orders" | grep "query_id"
# Output: [dbt-snowflake]query_id: 01b12345-6789...
```

**In Snowflake**:
```sql
select
  query_id,
  query_text,
  execution_time,
  queued_provision_time,
  compilation_time,
  (select count(*) from execution_statistics where query_id = q.query_id) as scans
from snowflake.account_usage.query_history q
where query_id = '01b12345-6789...'
;

-- Check query plan
select * from table(result_scan('01b12345-6789...'));
```

**Common slow patterns**:
- `queued_provision_time > 0`: Warehouse too small, scale up
- High scans + small execution: Lots of metadata lookups, add clustering key
- Many hash joins: Broadcast mismatch, check join order

### Using dbt.testing to Isolate Logic Bugs

**Unit tests** (dbt 1.8+): Test model logic without hitting warehouse
```yaml
unit_tests:
  - name: test_discount_calculation
    model: fct_orders
    given:
      - input: ref('stg_orders')
        rows:
          - {order_total: 100, discount_pct: 0.1}
    expect:
      rows:
        - {order_total: 100, discount_pct: 0.1, discounted_total: 90}
```

**Run unit tests before full build**:
```bash
dbt build  # Runs unit tests first, then models, then data tests
```

---

## 11. Multi-Team Workflow Best Practices

### Feature Branch Strategy

**Standard flow**:
```
main (prod) ← develop ← feature/org-refactor ← (your PR)
                              ↑
                    (all PRs merge here first)
                    (slim CI runs here)
```

**Why develop branch**:
- CI runs on develop before merging to main
- Catches integration issues (multiple PRs breaking each other)
- Rollback simpler (revert single commit on main)

### CI Pipeline: Slim + Fast

**Recommended GitHub Actions setup**:
```yaml
name: dbt slim CI

on:
  pull_request:
    paths:
      - 'models/**'
      - 'dbt_project.yml'
      - 'packages.yml'

jobs:
  dbt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Need full history for state comparison

      - name: Lint with SQLFluff
        run: sqlfluff lint models/

      - name: dbt parse (compile check)
        run: dbt parse

      - name: dbt build (slim CI)
        run: dbt build --select state:modified+ --state ./prod-manifest/ --defer

      - name: dbt test
        run: dbt test --select state:modified+
```

**Key params**:
- `--state ./prod-manifest/`: Use last prod manifest for comparison
- `--select state:modified+`: Only run changed models + downstream
- `--defer`: Use prod values for unchanged upstream (avoid re-running everything)

---

## Quick Reference

### Decision Trees

**Q: Should I create a new model or extend an existing one?**
```
Does the new logic belong to same entity (e.g., order)?
├─ YES: Extend existing model (add CTE)
└─ NO: Create intermediate or mart model
```

**Q: What materialization should this model be?**
```
Is it a staging model?
├─ YES: view (lightweight, 1:1 with source)
Is it downstream-facing (BI, ML, or 3+ consumers)?
├─ YES: table (cache for performance)
Is it used internally, 1-2 places?
├─ YES: ephemeral (CTE, no storage cost)
Is it 100M+ rows, time-series?
├─ YES: incremental (avoid re-processing)
```

**Q: How long should my deprecation period be?**
```
Is it a critical model (BI dashboards, reverse ETL)?
├─ YES: 90 days (long migration window)
Is it internal-facing (other dbt models only)?
├─ YES: 30 days (fast cutover)
Is it a brand new model?
├─ YES: No deprecation needed (no old version to replace)
```

---

## Related Resources

- **Foundational**: `docs/dbt-state-of-the-art-2025.md`
- **dbt Labs guides**: https://docs.getdbt.com/guides
- **Coalesce talks**: Search "Coalesce 2024" for video talks on scaling dbt
- **Community**: dbt Discourse for specific questions, r/dataengineering for war stories
- **Tools**: dbt Project Evaluator, Recce, dbt-loom, dbt-meshify
