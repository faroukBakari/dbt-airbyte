#!/bin/bash
#
# ELT Pipeline Runner & Monitor
# ==============================
# Triggers the elt_pipeline DAG and monitors task execution in real-time.
#
# Usage:
#   ./scripts/run_pipeline.sh
#

# NOTE: Do NOT use 'set -e' here - check_completion returns non-zero for "still running"

# =============================================================================
# CONFIGURATION
# =============================================================================
DAG_ID="elt_pipeline"
POLL_INTERVAL=3  # seconds between status checks
MAX_WAIT=900     # 15 minutes max wait time

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Task state colors
state_color() {
    case "$1" in
        success)  echo -e "${GREEN}✓ success${NC}" ;;
        running)  echo -e "${CYAN}► running${NC}" ;;
        failed)   echo -e "${RED}✗ failed${NC}" ;;
        skipped)  echo -e "${GRAY}○ skipped${NC}" ;;
        upstream_failed) echo -e "${RED}↑ upstream_failed${NC}" ;;
        queued)   echo -e "${YELLOW}◎ queued${NC}" ;;
        None|"")  echo -e "${GRAY}· pending${NC}" ;;
        *)        echo -e "${GRAY}? $1${NC}" ;;
    esac
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    # Move cursor to top-left and clear screen (works better in terminals)
    printf '\033[H\033[2J'
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  ${BOLD}ELT Pipeline Monitor${NC}${BLUE} - $DAG_ID${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

cleanup_existing_runs() {
    echo -e "${YELLOW}▶ Checking for existing DAG runs...${NC}"

    # Get count of non-terminal runs (queued, running)
    local active_runs=0
    local dag_exists
    dag_exists=$(docker exec airflow airflow dags list -o plain 2>/dev/null | grep -c "$DAG_ID" || true)

    if [[ "$dag_exists" -gt 0 ]]; then
        # Check for running DAG runs
        local running_count
        running_count=$(docker exec airflow airflow dags list-runs -d "$DAG_ID" -o plain 2>/dev/null \
            | grep -cE '\srunning\s' || true)
        active_runs=${running_count:-0}
    fi

    if [[ "$active_runs" -gt 0 ]]; then
        echo -e "  Found active run(s). Cleaning up..."

        # Delete the entire DAG (removes all run history) and let it re-parse
        docker exec airflow airflow dags delete "$DAG_ID" -y &>/dev/null || true

        # Wait for DAG to be re-parsed (with longer timeout)
        echo -e "  ${GRAY}Waiting for DAG to re-parse...${NC}"
        local wait_count=0
        while [[ $wait_count -lt 15 ]]; do
            if docker exec airflow airflow dags list 2>/dev/null | grep -q "$DAG_ID"; then
                break
            fi
            sleep 1
            ((wait_count++))
        done

        echo -e "${GREEN}✓ Cleaned up existing runs${NC}"
    else
        echo -e "${GREEN}✓ No active runs found${NC}"
    fi

    # Ensure DAG is unpaused (with retry to handle race condition)
    echo -e "${YELLOW}▶ Ensuring DAG is unpaused...${NC}"
    local unpause_attempts=0
    while [[ $unpause_attempts -lt 5 ]]; do
        if docker exec airflow airflow dags unpause "$DAG_ID" &>/dev/null; then
            # Verify it's actually unpaused
            if docker exec airflow airflow dags list -o plain 2>/dev/null | grep "$DAG_ID" | grep -q "False"; then
                break
            fi
        fi
        sleep 1
        ((unpause_attempts++))
    done
    echo -e "${GREEN}✓ DAG is active${NC}"
    echo ""
}

trigger_dag() {
    echo -e "${YELLOW}▶ Triggering DAG: ${DAG_ID}${NC}"

    # Trigger and capture output (filter out log lines, keep only JSON)
    local output
    output=$(docker exec airflow airflow dags trigger "$DAG_ID" -o json 2>/dev/null | grep '^\[{')

    # Extract run_id from JSON output
    RUN_ID=$(echo "$output" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['dag_run_id'])" 2>/dev/null)

    if [[ -z "$RUN_ID" ]]; then
        echo -e "${RED}✗ Failed to trigger DAG${NC}"
        echo "$output"
        exit 1
    fi

    echo -e "${GREEN}✓ DAG triggered successfully${NC}"
    echo -e "  Run ID: ${CYAN}${RUN_ID}${NC}"
    echo ""
}

get_task_states() {
    docker exec airflow airflow tasks states-for-dag-run "$DAG_ID" "$RUN_ID" 2>/dev/null | tail -n +3
}

get_dag_state() {
    docker exec airflow airflow dags list-runs -d "$DAG_ID" -o plain 2>/dev/null | grep "$RUN_ID" | awk '{print $3}'
}

print_task_table() {
    local states="$1"
    local elapsed="$2"

    print_header

    echo -e "  ${GRAY}Run ID:${NC} ${RUN_ID}"
    echo -e "  ${GRAY}Elapsed:${NC} ${elapsed}s"
    echo ""

    echo "┌──────────────────────────┬───────────────────────┬──────────────────────────────────┐"
    echo "│ Task                     │ State                 │ Duration                         │"
    echo "├──────────────────────────┼───────────────────────┼──────────────────────────────────┤"

    echo "$states" | while IFS='|' read -r dag_id exec_date task_id state start_date end_date; do
        # Clean up whitespace
        task_id=$(echo "$task_id" | xargs)
        state=$(echo "$state" | xargs)
        start_date=$(echo "$start_date" | xargs)
        end_date=$(echo "$end_date" | xargs)

        # Skip header lines
        [[ "$task_id" == "task_id" ]] && continue
        [[ "$task_id" == *"="* ]] && continue
        [[ -z "$task_id" ]] && continue

        # Calculate duration
        local duration="-"
        if [[ -n "$start_date" && "$start_date" != "None" ]]; then
            if [[ -n "$end_date" && "$end_date" != "None" && "$end_date" != "" ]]; then
                # Both start and end exist - calculate duration
                local start_ts=$(date -d "$start_date" +%s 2>/dev/null || echo "0")
                local end_ts=$(date -d "$end_date" +%s 2>/dev/null || echo "0")
                if [[ "$start_ts" != "0" && "$end_ts" != "0" ]]; then
                    local diff=$((end_ts - start_ts))
                    duration="${diff}s"
                fi
            elif [[ "$state" == "running" ]]; then
                # Running - show elapsed
                local start_ts=$(date -d "$start_date" +%s 2>/dev/null || echo "0")
                local now_ts=$(date +%s)
                if [[ "$start_ts" != "0" ]]; then
                    local diff=$((now_ts - start_ts))
                    duration="${diff}s (running)"
                fi
            fi
        fi

        # Get colored state (need to handle in subshell)
        local state_display
        case "$state" in
            success)  state_display="${GREEN}✓ success${NC}" ;;
            running)  state_display="${CYAN}► running${NC}" ;;
            failed)   state_display="${RED}✗ failed${NC}" ;;
            skipped)  state_display="${GRAY}○ skipped${NC}" ;;
            upstream_failed) state_display="${RED}↑ upstream_failed${NC}" ;;
            queued)   state_display="${YELLOW}◎ queued${NC}" ;;
            None|"")  state_display="${GRAY}· pending${NC}" ;;
            *)        state_display="${GRAY}? $state${NC}" ;;
        esac

        # Print row (accounting for ANSI codes in state)
        printf "│ %-24s │ %-32b │ %-32s │\n" "$task_id" "$state_display" "$duration"
    done

    echo "└──────────────────────────┴───────────────────────┴──────────────────────────────────┘"
    echo ""
}

check_completion() {
    local states="$1"

    # Check for any failed tasks
    if echo "$states" | grep -qE '\|\s*(failed|upstream_failed)\s*\|'; then
        return 1  # Failed
    fi

    # Check if all tasks are done (no running, queued, or pending)
    if echo "$states" | grep -qE '\|\s*(running|queued)\s*\|'; then
        return 2  # Still running
    fi

    # Check if pipeline_complete succeeded (fixed: was broken pipe)
    if echo "$states" | grep 'pipeline_complete' | grep -qE '\|\s*success\s*\|'; then
        return 0  # Success
    fi

    # Check DAG state directly
    local dag_state
    dag_state=$(get_dag_state)

    case "$dag_state" in
        success) return 0 ;;
        failed)  return 1 ;;
        running) return 2 ;;
        queued)  return 2 ;;
        *)       return 2 ;;  # Still waiting
    esac
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}ELT Pipeline Runner${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Check if Airflow is running
    if ! docker exec airflow airflow version &>/dev/null; then
        echo -e "${RED}✗ Airflow container is not running${NC}"
        echo "  Start it with: docker compose up -d"
        exit 1
    fi

    # Clean up any existing runs first
    cleanup_existing_runs

    # Trigger the DAG
    trigger_dag

    # Wait a moment for tasks to be scheduled
    sleep 2

    # Monitor loop
    local start_time=$(date +%s)
    local elapsed=0

    while [[ $elapsed -lt $MAX_WAIT ]]; do
        # Get current states
        local states
        states=$(get_task_states)

        # Calculate elapsed time
        elapsed=$(($(date +%s) - start_time))

        # Print the table
        print_task_table "$states" "$elapsed"

        # Check completion
        check_completion "$states"
        local result=$?

        if [[ $result -eq 0 ]]; then
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  ✓ Pipeline completed successfully!${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            exit 0
        elif [[ $result -eq 1 ]]; then
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${RED}  ✗ Pipeline failed!${NC}"
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "View logs with:"
            echo "  docker exec airflow airflow tasks logs $DAG_ID <task_id> $RUN_ID"
            echo ""
            exit 1
        fi

        # Still running - wait and poll again
        sleep $POLL_INTERVAL
    done

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ⚠ Timeout waiting for pipeline (${MAX_WAIT}s)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
}

main "$@"
