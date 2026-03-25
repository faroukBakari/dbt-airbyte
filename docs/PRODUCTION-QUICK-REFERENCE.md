# dbt Production Quick Reference

One-page lookup for common production scenarios. Full guidance: `docs/dbt-production-playbook-2025.md`.

---

## Refactoring

| Need | Pattern | Key Command |
|------|---------|-------------|
| Rename model safely | Alias v1 + deprecate, create v2, migrate refs | `config: {alias: new_name}` + `versions: {v: 1, deprecation_date}` |
| Change materialization | Create new model in parallel, audit with audit_helper, cutover | `dbt run -s new_model --full-refresh` |
| Split large model | Extract CTE to intermediate, audit rows match, update parent ref | `dbt build && dbt test -s int_model` |
| Remove unused column | Use model versioning, exclude column in v2, set deprecation_date | `versions: {v: 2, columns: {exclude: [old_col]}}` |

---

## Schema Migrations

| Scenario | Config | Notes |
|----------|--------|-------|
| Upstream adds columns (staging) | `on_schema_change: append_new_columns` | New columns are NULL for historical rows |
| Strict schema match (marts) | `on_schema_change: sync_all_columns` | Removes missing columns automatically |
| Reject mismatches | `on_schema_change: fail` | Default; safest for catching surprises |
| Change column logic | Full refresh incremental quarterly + manual update | Never change logic of existing column; add new column instead |

---

## Performance Debugging

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Model runs in 120s | Parse run_results.json; check top 10 slowest | Break into intermediate tables; check for SELECT * |
| View chain 4+ deep | Execution cascades through all views | Materialize as table at layer 3 |
| Incremental runs slower over time | No partition pruning, scanning all historical data | Add `where created_date > ...` with `is_incremental()` |
| Join slow on large tables | Missing broadcast hint, hash join expensive | Broadcast smaller table; check join selectivity |

**Extract slowest models**:
```bash
python3 -c "import json; results = json.load(open('target/run_results.json'));
print('\n'.join(sorted([(r['unique_id'].split('.')[-1], r['execution_time'])
for r in results['results']], key=lambda x: x[1], reverse=True)[:10]))"
```

---

## Upgrades

| Version | Breaking Change | Action |
|---------|-----------------|--------|
| 1.8 | Adapters decouple; must install `dbt-core` + `dbt-<adapter>` | `pip install dbt-core==1.8 dbt-snowflake==1.9` |
| 1.9 | `{{ target.account }}` dashes (Snowflake); microbatch available | Test incremental models; search for target.account refs |
| 1.10 | YAML deprecation warnings on by default | Run `dbt-autofix scan && dbt-autofix apply` |
| 1.11 | Redshift connection retry options | No action for most users |

**Safe upgrade**:
```bash
# 1. Test in dev
pip install dbt-core==X.Y dbt-<adapter>==X.Y
dbt parse && dbt build

# 2. Auto-fix deprecations (dry-run first)
dbt-autofix scan
dbt-autofix apply --behavior-change

# 3. Merge + deploy to prod
```

---

## Incidents

| Failure | Root Cause | Recovery |
|---------|-----------|----------|
| Stale data (yesterday's rows) | Source freshness missed; set to warn not error | `dbt source freshness --warn-error` before build |
| Schema drift (column not found) | Upstream added/removed columns; `on_schema_change: fail` | Set `append_new_columns` on staging; `dbt run --full-refresh` |
| Test fails; data looks right | Flaky test (timing, randomness, concurrent runs) | Check test logic; add ORDER BY; serialize runs; check for competing dbt runs |
| Incremental has duplicates | `unique_key` missing or wrong | `dbt run --full-refresh` on affected model; audit with audit_helper |

**Rollback checklist**:
1. Is data wrong or is model wrong? (check actual vs expected row count)
2. Can I fix forward (run dbt with fix + re-run)? Do that.
3. If must rollback: `git revert HEAD && dbt run --full-refresh --target prod`
4. Document: What broke? Why? How prevent next time?

---

## Code Review

### What to check as reviewer:

- **Scope**: Changes span 1-3 models? Or 5+ domains (warning sign)
- **Tests**: Every new column tested? Critical models have unit tests?
- **Breaking**: Is this a rename, removal, or logic change? If yes, is deprecation_date set?
- **Materialization**: Why this choice? Justified in PR?
- **Naming**: Follows `stg_`, `int_`, `fct_`, `dim_` prefixes?
- **Downstream**: How many models affected? Use `dbt ls -s state:modified+` to check.
- **SQL**: Any SELECT *? Missing partition filters? Inefficient joins?

**Assess impact**:
```bash
# In PR branch
dbt ls -s state:modified+  # How many models affected?
```

---

## Scaling (500+ models)

| Signal | Action |
|--------|--------|
| Parse time > 60s | Consider splitting into multi-project (Mesh) |
| 3+ teams, unclear ownership | Establish domain boundaries; extract team projects |
| Frequent CI conflicts (different teams) | Move teams to separate projects; use dbt Mesh for cross-refs |

**Mesh readiness**:
- dbt 1.5+? (contracts + model versioning)
- Clear domain structure? (finance, marketing, product, etc.)
- CI/CD in place? (Airflow/Dagster orchestration)

If yes → Start Phase 1 (prepare + run evaluator). If no → Stay monolith.

---

## Key Tools

| Problem | Tool | Link |
|---------|------|------|
| Find broken best practices | dbt Project Evaluator | `dbt-labs/dbt-project-evaluator` |
| Audit refactoring (new vs old data match) | dbt audit_helper | `dbt-labs/dbt-audit-helper` |
| Impact analysis in PR | Recce | `github.com/getrecce/recce` |
| Code review + data diff | Datafold | `datafold.com` |
| Auto-fix deprecations | dbt-autofix | `dbt-labs/dbt-autofix` |
| Cross-project refs (open-source Mesh) | dbt-loom | `garyblake/dbt-loom` |
| Auto-split monolith to Mesh | dbt_meshify | `dbt-labs/dbt-meshify` |

---

## Decision Tree: Deprecation Timeline

```
Is this a breaking change?
├─ NO: Ship without deprecation
└─ YES: Set deprecation_date
    ├─ Critical model (BI, dashboards, reverse ETL)? → 90 days
    ├─ Internal model (other dbt models only)? → 30 days
    └─ New model (no old version)? → No deprecation needed
```

---

## Common Configs (Copy-Paste)

### Safe staging model (append new columns):
```yaml
models:
  - name: stg_customers
    config:
      materialized: view
      on_schema_change: append_new_columns
    description: "1:1 with source, auto-appends new columns"
    columns:
      - name: customer_id
        data_type: bigint
        constraints:
          - type: not_null
```

### Safe incremental (with schema change handling):
```yaml
models:
  - name: fct_orders
    config:
      materialized: incremental
      unique_key: order_id
      on_schema_change: sync_all_columns
    columns:
      - name: order_id
        constraints:
          - type: not_null
```

### Versioned model with deprecation:
```yaml
models:
  - name: dim_customers
    latest_version: 2
    versions:
      - v: 1
        deprecation_date: "2025-06-30"
        columns:
          - include: all
            exclude: [legacy_field]
      - v: 2
        columns:
          - include: all
```

---

## Checklists

### Pre-commit checklist:
- [ ] Tests added for new models (not_null, unique on PK)
- [ ] dbt parse passes
- [ ] No SELECT * in new models
- [ ] dbt build runs successfully
- [ ] run_results.json shows execution times < 60s for new models
- [ ] Materialization choice documented (if unusual)

### Pre-merge checklist (code review):
- [ ] Scope is 1-3 models (not 5+)
- [ ] No breaking changes OR deprecation_date set
- [ ] Downstream impact < 50 models
- [ ] All tests pass in CI
- [ ] No hardcoded values (env vars or dbt_project.yml)
- [ ] PR description includes "why" not just "what"

### Post-incident checklist:
- [ ] Root cause documented in Slack
- [ ] Ticket created for prevention (monitoring, test, CI check)
- [ ] Team alerted (if it affects their models)
- [ ] Run_results.json + dbt debug logs saved for analysis

---

## Common Mistakes to Avoid

| Mistake | Why Bad | Fix |
|---------|---------|-----|
| Changing materialization without audit | Data may differ; silent corruption | Create new model, audit_helper.compare_relations(), migrate refs |
| Multiple CTEs > 4 deep, all ephemeral | Debugging impossible, inlining everywhere | Materialize layer 3 as table or view |
| `on_schema_change: fail` on staging | One upstream column addition breaks pipeline | Set `append_new_columns` for staging, `sync_all_columns` for marts |
| Renaming model without alias | Breaks downstream immediately | Use `alias: new_name` + `versions` + `deprecation_date` |
| No `unique_key` on merge incremental | Duplicates accumulate quietly | Always set `unique_key`; test with audit_helper |
| Test marked `severity: error` on unstable model | Alert fatigue; errors ignored | Use `warn` for legacy, `error` for new models only |
| Full test suite in CI | 30min CI, slow feedback | Slim CI: `--select state:modified+` |
| Upgrading dbt without testing | Breaking changes surprise you in prod | Test 1.7→1.8→1.9 in dev first; run dbt-autofix |
| No exposures for BI models | Orphaned models removed, dashboards break | Add exposures: `type: dashboard, depends_on: [ref(...)]` |
| Hardcoded table names in SQL | Model logic tied to specific schema | Use `{{ ref() }}` + `{{ source() }}` always |

---

## See Also

- **Full playbook**: `docs/dbt-production-playbook-2025.md`
- **Foundational**: `docs/dbt-state-of-the-art-2025.md`
- **dbt Labs**: https://docs.getdbt.com
