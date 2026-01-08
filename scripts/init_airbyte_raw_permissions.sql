-- ============================================================
-- Run this script CONNECTED TO airbyte_raw database
-- Grants dbt read access to Airbyte tables
-- ============================================================

-- Grant schema usage and table read to dbt_user
GRANT USAGE ON SCHEMA public TO dbt_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbt_user;

-- Ensure future tables created by Airbyte are also readable
ALTER DEFAULT PRIVILEGES FOR USER airbyte_user IN SCHEMA public
    GRANT SELECT ON TABLES TO dbt_user;

SELECT 'Permissions configured for airbyte_raw!' AS status;
