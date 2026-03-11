"""
ELT Pipeline DAG - Airbyte + dbt POC
=====================================
Orchestrates the full ELT workflow:
1. Trigger Airbyte sync (or seed test data as fallback)
2. Run dbt staging models
3. Run dbt mart models
4. Run dbt gold models
5. Run dbt tests

Modes:
- With Airbyte: Triggers sync via API (requires AIRBYTE_CONNECTION_ID variable)
- Without Airbyte: Uses seed_test_data.sql as fallback
"""

import os
from datetime import datetime, timedelta
from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.empty import EmptyOperator

# Environment variables (loaded from .env.generated via docker-compose)
POSTGRES_CONTAINER = os.getenv('POSTGRES_CONTAINER', 'postgres')
POSTGRES_USER = os.getenv('POSTGRES_USER', 'postgres')
AIRBYTE_DB_NAME = os.getenv('AIRBYTE_DB_NAME', 'airbyte_raw')
AIRBYTE_WEB_USER = os.getenv('AIRBYTE_WEB_USER', 'airbyte')
AIRBYTE_WEB_PASSWORD = os.getenv('AIRBYTE_WEB_PASSWORD', 'password')

# Default arguments for all tasks
default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=2),
}

# DAG definition
with DAG(
    dag_id='elt_pipeline',
    default_args=default_args,
    description='ELT Pipeline: Airbyte/Faker → Raw → Staging → Marts → Gold',
    schedule_interval=None,  # Manual trigger for POC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['poc', 'elt', 'dbt', 'airbyte'],
) as dag:

    # ==========================================================================
    # Task 0: Check if Airbyte is configured
    # ==========================================================================
    def check_airbyte_mode(**context):
        """Branch based on whether Airbyte connection ID is configured."""
        try:
            connection_id = Variable.get('airbyte_connection_id', default_var=None)
            if connection_id and connection_id.strip():
                print(f"✅ Airbyte mode: Using connection ID {connection_id}")
                return 'trigger_airbyte_sync'
            else:
                print("ℹ️ Seed mode: No Airbyte connection configured")
                return 'seed_raw_data'
        except Exception as e:
            print(f"ℹ️ Seed mode: {e}")
            return 'seed_raw_data'

    check_mode = BranchPythonOperator(
        task_id='check_data_source_mode',
        python_callable=check_airbyte_mode,
        doc_md="""
        ### Check Data Source Mode
        Determines whether to use Airbyte or seed data based on configuration.
        Set `airbyte_connection_id` variable in Airflow to enable Airbyte mode.
        """,
    )

    # ==========================================================================
    # Task 1a: Trigger Airbyte Sync (if configured)
    # ==========================================================================
    trigger_airbyte_sync = BashOperator(
        task_id='trigger_airbyte_sync',
        bash_command='''
            CONNECTION_ID="{{ var.value.airbyte_connection_id }}"
            AIRBYTE_AUTH="${AIRBYTE_WEB_USER:-airbyte}:${AIRBYTE_WEB_PASSWORD:-password}"
            echo "Triggering Airbyte sync for connection: $CONNECTION_ID"

            # Trigger sync via Airbyte API
            RESPONSE=$(curl -s -X POST "http://airbyte-proxy:8000/api/v1/connections/sync" \
                -u "$AIRBYTE_AUTH" \
                -H "Content-Type: application/json" \
                -d '{"connectionId": "'"$CONNECTION_ID"'"}')

            echo "Response: $RESPONSE"

            # Extract job ID using Python for robust JSON parsing
            JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('job',{}).get('id',''))" 2>/dev/null)

            if [ -z "$JOB_ID" ]; then
                echo "❌ Failed to start Airbyte sync - could not parse job ID from response"
                echo "Raw response: $RESPONSE"
                exit 1
            fi

            echo "✅ Airbyte sync started with job ID: $JOB_ID"

            # Poll for completion (max 10 minutes)
            for i in $(seq 1 60); do
                sleep 10
                STATUS=$(curl -s -X POST "http://airbyte-proxy:8000/api/v1/jobs/get" \
                    -u "$AIRBYTE_AUTH" \
                    -H "Content-Type: application/json" \
                    -d '{"id": '"$JOB_ID"'}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('job',{}).get('status',''))" 2>/dev/null)

                echo "Job status: $STATUS (attempt $i/60)"

                if [ "$STATUS" = "succeeded" ]; then
                    echo "✅ Airbyte sync completed successfully!"
                    exit 0
                elif [ "$STATUS" = "failed" ] || [ "$STATUS" = "cancelled" ]; then
                    echo "❌ Airbyte sync failed with status: $STATUS"
                    exit 1
                fi
            done

            echo "⚠️ Timeout waiting for Airbyte sync"
            exit 1
        ''',
        doc_md="""
        ### Trigger Airbyte Sync
        Triggers a sync for the configured Airbyte connection and waits for completion.
        Requires `airbyte_connection_id` Airflow variable to be set.
        """,
    )

    # ==========================================================================
    # Task 1b: Seed raw data (fallback when Airbyte not configured)
    # ==========================================================================
    seed_raw_data = BashOperator(
        task_id='seed_raw_data',
        bash_command=f'docker exec -i {POSTGRES_CONTAINER} psql -U {POSTGRES_USER} -d {AIRBYTE_DB_NAME} < /opt/airflow/scripts/seed_test_data.sql',
        doc_md=f"""
        ### Seed Raw Data
        Loads sample data into `{AIRBYTE_DB_NAME}` database.
        This is the fallback when Airbyte is not configured.
        """,
    )

    # ==========================================================================
    # Join point after data load
    # ==========================================================================
    data_loaded = EmptyOperator(
        task_id='data_loaded',
        trigger_rule='none_failed_min_one_success',
    )

    # Task 2: Run dbt staging models (raw → staging views)
    dbt_run_staging = BashOperator(
        task_id='dbt_run_staging',
        bash_command='docker exec dbt-runner dbt run --select staging',
        doc_md="""
        ### dbt Staging
        Transforms raw JSON data into typed, cleaned views.
        - stg_users
        - stg_products
        - stg_purchases
        """,
    )

    # Task 3: Run dbt mart models (staging → mart tables)
    dbt_run_marts = BashOperator(
        task_id='dbt_run_marts',
        bash_command='docker exec dbt-runner dbt run --select marts',
        doc_md="""
        ### dbt Marts
        Builds business-focused dimension tables.
        - dim_users (with purchase aggregates)
        """,
    )

    # Task 4: Run dbt gold models (marts → gold tables)
    dbt_run_gold = BashOperator(
        task_id='dbt_run_gold',
        bash_command='docker exec dbt-runner dbt run --select gold',
        doc_md="""
        ### dbt Gold Layer
        Creates final analytics-ready tables for BI consumption.
        - gold_user_purchases
        """,
    )

    # Task 5: Run dbt tests (data quality validation)
    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command='docker exec dbt-runner dbt test',
        doc_md="""
        ### dbt Tests
        Validates data quality across all models.
        """,
    )

    # Task 6: Log completion
    def log_completion(**context):
        print("=" * 50)
        print("✅ ELT Pipeline completed successfully!")
        print(f"   Execution date: {context['ds']}")
        print(f"   Run ID: {context['run_id']}")
        print("=" * 50)

    pipeline_complete = PythonOperator(
        task_id='pipeline_complete',
        python_callable=log_completion,
    )

    # Define task dependencies
    # Branch: check_mode → (trigger_airbyte_sync OR seed_raw_data) → data_loaded
    check_mode >> [trigger_airbyte_sync, seed_raw_data]
    trigger_airbyte_sync >> data_loaded
    seed_raw_data >> data_loaded

    # Sequential dbt flow
    data_loaded >> dbt_run_staging >> dbt_run_marts >> dbt_run_gold >> dbt_test >> pipeline_complete
