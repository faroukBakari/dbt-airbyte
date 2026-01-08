"""
ELT Pipeline DAG - Airbyte + dbt POC
=====================================
Orchestrates the full ELT workflow:
1. Seed raw data (simulates Airbyte extract/load)
2. Run dbt staging models
3. Run dbt mart models  
4. Run dbt gold models
5. Run dbt tests
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

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
    description='ELT Pipeline: Faker → Raw → Staging → Marts → Gold',
    schedule_interval=None,  # Manual trigger for POC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['poc', 'elt', 'dbt'],
) as dag:

    # Task 1: Seed raw data (simulates Airbyte loading Faker data)
    seed_raw_data = BashOperator(
        task_id='seed_raw_data',
        bash_command='''
            docker exec n8n-postgres psql -U postgres -d airbyte_raw -f /dev/stdin < /opt/airflow/scripts/seed_test_data.sql
        ''',
        doc_md="""
        ### Seed Raw Data
        Loads sample data into `airbyte_raw` database.
        This simulates what Airbyte would do with the Sample Data (Faker) connector.
        """,
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

    # Define task dependencies (sequential flow)
    seed_raw_data >> dbt_run_staging >> dbt_run_marts >> dbt_run_gold >> dbt_test >> pipeline_complete
