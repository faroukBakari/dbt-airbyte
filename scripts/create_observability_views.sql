-- =============================================================================
-- Observability Views for Elementary Data
-- =============================================================================
-- Creates PostgreSQL views in the elementary schema that power the
-- Metabase "Data Quality & Observability" dashboard.
--
-- All views use CREATE OR REPLACE — safe to re-run after schema changes.
-- Run via: bash scripts/create_observability_views.sh
-- =============================================================================

-- 1. Test pass rate trend — headline time-series chart
CREATE OR REPLACE VIEW elementary.v_test_pass_rate_trend AS
SELECT
    detected_at::date AS run_date,
    invocation_id,
    COUNT(*) AS total_tests,
    COUNT(*) FILTER (WHERE status = 'pass') AS passed,
    COUNT(*) FILTER (WHERE status != 'pass') AS failed,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE status = 'pass')
        / NULLIF(COUNT(*), 0),
        1
    ) AS pass_rate_pct
FROM elementary.elementary_test_results
GROUP BY detected_at::date, invocation_id
ORDER BY detected_at::date DESC;

-- 2. Test results by model — breakdown by model and layer
CREATE OR REPLACE VIEW elementary.v_test_results_by_model AS
SELECT
    schema_name AS layer,
    table_name AS model,
    test_type,
    status,
    COUNT(*) AS test_count,
    detected_at::date AS run_date,
    invocation_id
FROM elementary.elementary_test_results
GROUP BY schema_name, table_name, test_type, status, detected_at::date, invocation_id
ORDER BY schema_name, table_name;

-- 3. Model execution times — duration trends
CREATE OR REPLACE VIEW elementary.v_model_execution_times AS
SELECT
    name AS model_name,
    materialization,
    execution_time,
    status,
    rows_affected,
    execute_started_at,
    invocation_id
FROM elementary.dbt_run_results
WHERE resource_type = 'model'
ORDER BY execute_started_at DESC;

-- 4. Invocation history — dbt run summary per invocation
CREATE OR REPLACE VIEW elementary.v_invocation_history AS
SELECT
    invocation_id,
    resource_type,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status IN ('success', 'pass')) AS passed,
    COUNT(*) FILTER (WHERE status NOT IN ('success', 'pass')) AS failed,
    ROUND(AVG(execution_time)::numeric, 2) AS avg_execution_time_s,
    MIN(execute_started_at) AS started_at,
    MAX(execute_completed_at) AS completed_at
FROM elementary.dbt_run_results
GROUP BY invocation_id, resource_type
ORDER BY started_at DESC;

-- 5. Latest test failures — drill-down for failures
CREATE OR REPLACE VIEW elementary.v_latest_test_failures AS
SELECT
    test_name,
    table_name,
    column_name,
    test_type,
    status,
    severity,
    failures,
    test_results_description,
    detected_at
FROM elementary.elementary_test_results
WHERE status != 'pass'
ORDER BY detected_at DESC;

-- 6. Test coverage by model — test coverage summary
CREATE OR REPLACE VIEW elementary.v_test_coverage_by_model AS
SELECT
    m.name AS model_name,
    m.schema_name AS layer,
    COUNT(DISTINCT t.test_unique_id) AS test_count,
    COUNT(DISTINCT t.column_name) AS columns_tested
FROM elementary.dbt_models m
LEFT JOIN elementary.elementary_test_results t
    ON t.model_unique_id = m.unique_id
GROUP BY m.name, m.schema_name
ORDER BY test_count DESC;
