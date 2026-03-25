#!/bin/bash
#
# Create Elementary observability views in PostgreSQL
# ====================================================
# Creates 6 SQL views in the elementary schema that power the
# Metabase "Data Quality & Observability" dashboard.
#
# Idempotent — safe to re-run (uses CREATE OR REPLACE VIEW).
#
# Usage:
#   bash scripts/create_observability_views.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SQL_FILE="$SCRIPT_DIR/create_observability_views.sql"

# Load environment
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${GEN_AIRBYTE_DB_NAME:-airbyte_raw}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ ! -f "$SQL_FILE" ]]; then
    echo -e "${RED}✗ SQL file not found: $SQL_FILE${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}▶ Creating observability views in elementary schema...${NC}"

# Check that elementary schema exists (populated by dbt build)
if ! docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB_NAME" -tAc \
    "SELECT 1 FROM information_schema.schemata WHERE schema_name='elementary'" 2>/dev/null | grep -q 1; then
    echo -e "${YELLOW}⚠ Elementary schema not found — run 'dbt build' first to populate Elementary tables${NC}" >&2
    exit 1
fi

# Check that at least one Elementary table exists
if ! docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB_NAME" -tAc \
    "SELECT 1 FROM information_schema.tables WHERE table_schema='elementary' AND table_name='elementary_test_results' LIMIT 1" 2>/dev/null | grep -q 1; then
    echo -e "${YELLOW}⚠ Elementary tables not populated — run 'dbt build' first${NC}" >&2
    exit 1
fi

# Execute the SQL file
if docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$DB_NAME" < "$SQL_FILE" 2>&1; then
    echo -e "${GREEN}✓ 6 observability views created in elementary schema${NC}"
    echo "  Views: v_test_pass_rate_trend, v_test_results_by_model,"
    echo "         v_model_execution_times, v_invocation_history,"
    echo "         v_latest_test_failures, v_test_coverage_by_model"
else
    echo -e "${RED}✗ Failed to create observability views${NC}" >&2
    exit 1
fi
