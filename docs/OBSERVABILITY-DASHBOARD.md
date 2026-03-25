# Data Quality & Observability Dashboard

Step-by-step guide to creating a live Metabase dashboard that queries Elementary's persistent test and model metadata tables.

## Prerequisites

- Metabase running at http://localhost:54892 (started by `docker-compose`)
- Elementary tables populated (`dbt build` completed at least once)
- Observability views created (`bash scripts/create_observability_views.sh`)

## SQL Views

Six views in the `elementary` schema power the dashboard:

| View | Purpose |
|------|---------|
| `v_test_pass_rate_trend` | Test pass rate over time (headline metric) |
| `v_test_results_by_model` | Test breakdown by model and layer |
| `v_model_execution_times` | Model build duration trends |
| `v_invocation_history` | dbt run summary per invocation |
| `v_latest_test_failures` | Recent test failures for drill-down |
| `v_test_coverage_by_model` | Test coverage per model |

Views are idempotent (`CREATE OR REPLACE`) — re-run `scripts/create_observability_views.sh` after any Elementary schema change.

---

## Dashboard Setup

### 1. Add Data Source (if not already done)

1. Open Metabase → **Settings** (gear icon) → **Admin** → **Databases** → **Add database**
2. Configure:
   - **Database type**: PostgreSQL
   - **Host**: `postgres`
   - **Port**: `5432`
   - **Database name**: `airbyte_raw`
   - **Username**: `dbt_user`
   - **Password**: `dbt_password`
3. Click **Save** → wait for sync to complete

### 2. Create Dashboard

1. Click **+ New** → **Dashboard**
2. Name: **Data Quality & Observability**
3. Add cards as described below

### 3. Row 1 — KPI Cards

Add 4 scalar cards across the top row:

**Total Tests**
```sql
SELECT total_tests
FROM elementary.v_test_pass_rate_trend
ORDER BY run_date DESC
LIMIT 1;
```
- Visualization: **Number**

**Pass Rate**
```sql
SELECT pass_rate_pct
FROM elementary.v_test_pass_rate_trend
ORDER BY run_date DESC
LIMIT 1;
```
- Visualization: **Number** (suffix: `%`)

**Models**
```sql
SELECT COUNT(*) AS model_count
FROM elementary.dbt_models;
```
- Visualization: **Number**

**Last Run**
```sql
SELECT MAX(completed_at) AS last_run
FROM elementary.v_invocation_history;
```
- Visualization: **Number** (date format)

### 4. Row 2 — Trend Charts

Add 2 half-width cards:

**Test Pass Rate Over Time**
```sql
SELECT run_date, pass_rate_pct, invocation_id
FROM elementary.v_test_pass_rate_trend
ORDER BY run_date ASC;
```
- Visualization: **Line chart**
- X-axis: `run_date`
- Y-axis: `pass_rate_pct`

**Model Execution Duration**
```sql
SELECT model_name, execution_time, execute_started_at
FROM elementary.v_model_execution_times
ORDER BY execute_started_at ASC;
```
- Visualization: **Line chart**
- X-axis: `execute_started_at`
- Y-axis: `execution_time`
- Series: `model_name`

### 5. Row 3 — Detail Tables

Add 2 cards:

**Test Results by Model (Latest Run)**
```sql
SELECT layer, model, test_type, status, test_count
FROM elementary.v_test_results_by_model
WHERE invocation_id = (
    SELECT invocation_id
    FROM elementary.v_test_pass_rate_trend
    ORDER BY run_date DESC
    LIMIT 1
)
ORDER BY layer, model;
```
- Visualization: **Table**
- Optional: conditional formatting on `status` column (green for pass, red for fail)

**Test Coverage**
```sql
SELECT model_name, layer, test_count, columns_tested
FROM elementary.v_test_coverage_by_model;
```
- Visualization: **Table**

### 6. Row 4 — Failures

Add 1 full-width card:

**Recent Test Failures**
```sql
SELECT test_name, table_name, column_name, test_type, severity, failures, detected_at
FROM elementary.v_latest_test_failures
ORDER BY detected_at DESC
LIMIT 50;
```
- Visualization: **Table** (red row styling recommended)

### 7. Dashboard Settings

1. Click the **pencil icon** to enter edit mode
2. Click the **clock icon** → set auto-refresh to **5 minutes**
3. Save the dashboard

---

## Verification

After creating the dashboard, verify each card shows data:

```bash
# Test pass rate trend
docker exec postgres psql -U dbt_user -d airbyte_raw \
  -c "SELECT * FROM elementary.v_test_pass_rate_trend;"

# Model execution times
docker exec postgres psql -U dbt_user -d airbyte_raw \
  -c "SELECT * FROM elementary.v_model_execution_times LIMIT 5;"

# Test coverage
docker exec postgres psql -U dbt_user -d airbyte_raw \
  -c "SELECT * FROM elementary.v_test_coverage_by_model;"
```

## Refreshing Views

Views query Elementary tables directly — they auto-refresh on every query. After a new `dbt build` run, the dashboard reflects updated data immediately (or within the 5-minute auto-refresh interval).

If Elementary schema changes (new columns, renamed tables), re-run:

```bash
bash scripts/create_observability_views.sh
```
