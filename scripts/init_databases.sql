-- ============================================================
-- POC Database Initialization Script
-- Creates users only - databases created separately via shell
-- ============================================================

-- Create dedicated user for dbt (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dbt_user') THEN
        CREATE USER dbt_user WITH PASSWORD 'dbt_password';
        RAISE NOTICE 'Created user: dbt_user';
    ELSE
        RAISE NOTICE 'User dbt_user already exists';
    END IF;
END
$$;

-- Create dedicated user for Airbyte (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'airbyte_user') THEN
        CREATE USER airbyte_user WITH PASSWORD 'airbyte_password';
        RAISE NOTICE 'Created user: airbyte_user';
    ELSE
        RAISE NOTICE 'User airbyte_user already exists';
    END IF;
END
$$;

SELECT 'Users created/verified successfully!' AS status;
