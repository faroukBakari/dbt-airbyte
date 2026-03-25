#!/bin/bash
# Generates Elementary observability report from host (WSL)
# Uses uvx for zero-install execution — no permanent packages needed.
#
# Prerequisites:
#   - uv installed (WSL)
#   - PostgreSQL reachable on localhost:5432 (Docker port mapping)
#   - dbt build has run at least once (populates Elementary tables)
#
# Usage:
#   bash scripts/generate_elementary_report.sh
#
# Output:
#   elementary-report/elementary_report.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Generating Elementary observability report..."

POSTGRES_HOST_DOCKER=localhost \
DBT_USER=dbt_user \
DBT_PASSWORD=dbt_password \
  uvx --python 3.12 --from elementary-data --with dbt-postgres==1.9.0 edr report \
    --profiles-dir "$PROJECT_ROOT/profiles" \
    --project-dir "$PROJECT_ROOT/dbt_project" \
    --file-path "$PROJECT_ROOT/elementary-report/elementary_report.html" \
    --open-browser false

REPORT_PATH="$PROJECT_ROOT/elementary-report/elementary_report.html"

echo ""
echo "Report generated: $REPORT_PATH"

if command -v wslview &> /dev/null; then
    echo "Opening in browser..."
    wslview "$REPORT_PATH"
else
    echo "Open in browser:  wslview elementary-report/elementary_report.html"
fi
