-- ============================================================
-- Run this script CONNECTED TO dbt_analytics database
-- Creates schemas for dbt layers: staging, marts, gold
-- ============================================================

-- Create schemas for each dbt layer
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS gold;

-- Grant dbt_user full access to all schemas
GRANT ALL PRIVILEGES ON SCHEMA staging TO dbt_user;
GRANT ALL PRIVILEGES ON SCHEMA marts TO dbt_user;
GRANT ALL PRIVILEGES ON SCHEMA gold TO dbt_user;

-- Grant usage on public schema as well
GRANT ALL PRIVILEGES ON SCHEMA public TO dbt_user;

-- Ensure dbt_user can create objects in these schemas
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT ALL ON TABLES TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts GRANT ALL ON TABLES TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT ALL ON TABLES TO dbt_user;

SELECT 'dbt_analytics schemas created: staging, marts, gold' AS status;
