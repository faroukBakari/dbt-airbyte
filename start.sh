#!/bin/bash
#
# Start the full dbt-airbyte POC stack
# =====================================
# Brings up all containers, configures Airbyte, and opens web consoles.
#
# Usage:
#   ./start.sh              # Start everything + open browsers
#   ./start.sh --no-browser # Start everything, skip browser opening
#
# Services started:
#   - PostgreSQL (external container)
#   - dbt-runner, Airflow, Metabase (docker-compose.yaml)
#   - Airbyte 8-container stack (docker-compose.airbyte.yaml)
#
# Airbyte is auto-configured with Faker source → PostgreSQL destination.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Parse args
OPEN_BROWSER=true
for arg in "$@"; do
    case "$arg" in
        --no-browser) OPEN_BROWSER=false ;;
        *) echo -e "${RED}Unknown argument: $arg${NC}"; exit 1 ;;
    esac
done

# -----------------------------------------------------------------------------
# 1. PostgreSQL (external container)
# -----------------------------------------------------------------------------
echo -e "\n${BLUE}[1/5]${NC} Starting PostgreSQL..."
if docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
    echo -e "${GREEN}  Already running${NC}"
else
    docker start postgres 2>/dev/null || {
        echo -e "${RED}  PostgreSQL container not found. Run ./scripts/setup.sh first.${NC}"
        exit 1
    }
    echo -e "${GREEN}  Started${NC}"
fi

# Wait for Postgres to accept connections
echo -n "  Waiting for connections..."
for i in $(seq 1 15); do
    if docker exec postgres pg_isready -U postgres -q 2>/dev/null; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo -e " ${RED}timeout${NC}"
        exit 1
    fi
    sleep 1
done

# -----------------------------------------------------------------------------
# 2. Core services (dbt, Airflow, Metabase)
# -----------------------------------------------------------------------------
echo -e "\n${BLUE}[2/5]${NC} Starting dbt, Airflow, Metabase..."
docker compose up -d 2>&1 | grep -v "orphan containers"
echo -e "${GREEN}  Started${NC}"

# -----------------------------------------------------------------------------
# 3. Airbyte (separate compose stack)
# -----------------------------------------------------------------------------
# Ensure airbyte_user has write permissions on public schema
# (seed data creates tables owned by postgres — Airbyte needs to overwrite them)
docker exec postgres psql -U postgres -d airbyte_raw -c "
    GRANT ALL ON SCHEMA public TO airbyte_user;
    GRANT ALL ON ALL TABLES IN SCHEMA public TO airbyte_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO airbyte_user;
" 2>/dev/null || true

echo -e "\n${BLUE}[3/5]${NC} Starting Airbyte (8 containers)..."
docker compose -f docker-compose.airbyte.yaml up -d 2>&1 | grep -v "orphan containers"
echo -e "${GREEN}  Started${NC}"

# -----------------------------------------------------------------------------
# 4. Wait for Airbyte API + configure
# -----------------------------------------------------------------------------
echo -e "\n${BLUE}[4/5]${NC} Waiting for Airbyte API..."
for i in $(seq 1 60); do
    response=$(curl -s -u airbyte:password http://localhost:8000/api/v1/health 2>/dev/null || true)
    if echo "$response" | grep -q '"available":true'; then
        echo -e "  ${GREEN}Airbyte API ready${NC}"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo -e "  ${RED}Airbyte API not ready after 60s — skipping configuration${NC}"
        echo -e "  ${YELLOW}Run manually: python3 scripts/configure_airbyte.py${NC}"
        break
    fi
    sleep 1
done

echo "  Configuring Airbyte (Faker → PostgreSQL)..."
connection_id=$(python3 scripts/configure_airbyte.py 2>/dev/null)
if [ -n "$connection_id" ]; then
    echo -e "  ${GREEN}Configured (connection: $connection_id)${NC}"
    # Set Airflow variable so run_pipeline.sh uses the Airbyte sync path
    if docker exec airflow airflow variables set airbyte_connection_id "$connection_id" &>/dev/null; then
        echo -e "  ${GREEN}Airflow variable set${NC}"
    fi
else
    echo -e "  ${YELLOW}Configuration failed — run manually: python3 scripts/configure_airbyte.py${NC}"
fi

# -----------------------------------------------------------------------------
# 5. Health summary
# -----------------------------------------------------------------------------
echo -e "\n${BLUE}[5/5]${NC} Verifying services..."
echo ""

check_service() {
    local name="$1" url="$2" auth="$3"
    local curl_args=(-s --max-time 5)
    [ -n "$auth" ] && curl_args+=(-u "$auth")
    if curl "${curl_args[@]}" "$url" 2>/dev/null | grep -qiE '"healthy"|"ok"|"available"'; then
        echo -e "  ${GREEN}✓${NC} $name"
    else
        echo -e "  ${YELLOW}⏳${NC} $name (still starting)"
    fi
}

check_service "PostgreSQL"  "" ""
docker exec postgres pg_isready -U postgres -q 2>/dev/null \
    && echo -e "  ${GREEN}✓${NC} PostgreSQL" \
    || echo -e "  ${YELLOW}⏳${NC} PostgreSQL"
check_service "Airflow"     "http://localhost:8080/health" ""
check_service "Airbyte"     "http://localhost:8000/api/v1/health" "airbyte:password"
check_service "Metabase"    "http://localhost:54892/api/health" ""

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Service URLs${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Airflow   ${GREEN}http://localhost:8080${NC}    admin / admin"
echo -e "  Airbyte   ${GREEN}http://localhost:8000${NC}    airbyte / password"
echo -e "  Metabase  ${GREEN}http://localhost:54892${NC}   (wizard-set credentials)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# -----------------------------------------------------------------------------
# Open browsers
# -----------------------------------------------------------------------------
if [ "$OPEN_BROWSER" = true ] && command -v wslview &>/dev/null; then
    echo -e "${YELLOW}Opening web consoles...${NC}"
    wslview "http://localhost:8080"  # Airflow
    sleep 0.5
    wslview "http://localhost:8000"  # Airbyte
    sleep 0.5
    wslview "http://localhost:54892" # Metabase
    echo -e "${GREEN}Done.${NC}"
elif [ "$OPEN_BROWSER" = true ]; then
    echo -e "${YELLOW}wslview not found — open the URLs above manually.${NC}"
fi
