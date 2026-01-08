#!/usr/bin/env python3
"""
Airbyte Auto-Configuration Script
==================================
Programmatically configures Airbyte Source (Faker), Destination (PostgreSQL),
and Connection for the dbt-airbyte POC.

Uses the legacy Config API (/api/v1) compatible with Airbyte OSS v0.50.5.
Zero external dependencies - uses only Python stdlib.

Usage:
    python3 scripts/configure_airbyte.py

Output:
    Prints the connection_id on success (for setup.sh to capture)
    Exit code 0 on success, 1 on failure
"""

import json
import sys
import urllib.request
import urllib.error
import base64
import os
from typing import Any

# =============================================================================
# CONFIGURATION (from environment variables with fallbacks)
# =============================================================================

AIRBYTE_URL = os.getenv("AIRBYTE_URL", "http://localhost:8000/api/v1")
AIRBYTE_USERNAME = os.getenv("AIRBYTE_WEB_USER", "airbyte")
AIRBYTE_PASSWORD = os.getenv("AIRBYTE_WEB_PASSWORD", "password")

# Source/Destination Definition IDs (from Airbyte API inspection)
FAKER_SOURCE_DEF_ID = "dfd88b22-b603-4c3d-aad7-3701784586b1"
POSTGRES_DEST_DEF_ID = "25c5221d-dce2-4163-ade9-739ef790f503"

# Source configuration (Faker)
SOURCE_NAME = "Sample Data (Faker)"
SOURCE_CONFIG = {
    "count": 100,
    "seed": 42,
    "parallelism": 4,
    "always_updated": False,
    "records_per_slice": 1000,
}

# Destination configuration (PostgreSQL -> airbyte_raw)
# NOTE: Use "localhost" because Airbyte connectors run with --network host
#       where Docker DNS (n8n-postgres) is not available.
_airbyte_db_name = os.getenv("AIRBYTE_DB_NAME", "airbyte_raw")
DESTINATION_NAME = f"PostgreSQL ({_airbyte_db_name})"
DESTINATION_CONFIG = {
    "host": os.getenv("POSTGRES_HOST_EXTERNAL", "localhost"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "database": _airbyte_db_name,
    "schema": "public",
    "username": os.getenv("AIRBYTE_DB_USER", "airbyte_user"),
    "password": os.getenv("AIRBYTE_DB_PASSWORD", "airbyte_password"),
    "ssl_mode": {"mode": "disable"},
    "tunnel_method": {"tunnel_method": "NO_TUNNEL"},
}

# Connection configuration
CONNECTION_NAME = f"Faker → PostgreSQL ({_airbyte_db_name})"


# =============================================================================
# API HELPER LAYER
# =============================================================================

def _api_request(endpoint: str, payload: dict) -> dict:
    """
    Make a POST request to the Airbyte Config API.
    
    Args:
        endpoint: API endpoint (e.g., "workspaces/list")
        payload: JSON payload to send
        
    Returns:
        Parsed JSON response
        
    Raises:
        SystemExit on HTTP errors
    """
    url = f"{AIRBYTE_URL}/{endpoint}"
    
    # Prepare request with Basic Auth
    credentials = base64.b64encode(
        f"{AIRBYTE_USERNAME}:{AIRBYTE_PASSWORD}".encode()
    ).decode()
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Basic {credentials}",
    }
    
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else "No details"
        print(f"✗ API Error [{e.code}] {endpoint}: {error_body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"✗ Connection Error: {e.reason}", file=sys.stderr)
        print("  Is Airbyte running? Check: docker ps | grep airbyte", file=sys.stderr)
        sys.exit(1)


def _log(message: str) -> None:
    """Print a status message to stderr (stdout reserved for connection_id)."""
    print(message, file=sys.stderr)


# =============================================================================
# IDEMPOTENT RESOURCE CREATION
# =============================================================================

def get_workspace_id() -> str:
    """Get the default workspace ID."""
    _log("→ Getting workspace ID...")
    response = _api_request("workspaces/list", {})
    workspaces = response.get("workspaces", [])
    
    if not workspaces:
        _log("✗ No workspaces found. Airbyte may not be initialized.")
        sys.exit(1)
    
    workspace_id = workspaces[0]["workspaceId"]
    _log(f"  Workspace: {workspace_id}")
    return workspace_id


def get_or_create_source(workspace_id: str) -> str:
    """Get existing or create new Faker source."""
    _log("→ Checking for existing source...")
    
    # Check if source already exists
    response = _api_request("sources/list", {"workspaceId": workspace_id})
    for source in response.get("sources", []):
        if source.get("name") == SOURCE_NAME:
            source_id = source["sourceId"]
            _log(f"  Found existing source: {source_id}")
            return source_id
    
    # Create new source
    _log("  Creating new source...")
    response = _api_request("sources/create", {
        "workspaceId": workspace_id,
        "sourceDefinitionId": FAKER_SOURCE_DEF_ID,
        "connectionConfiguration": SOURCE_CONFIG,
        "name": SOURCE_NAME,
    })
    
    source_id = response["sourceId"]
    _log(f"  ✓ Created source: {source_id}")
    return source_id


def get_or_create_destination(workspace_id: str) -> str:
    """Get existing or create new PostgreSQL destination."""
    _log("→ Checking for existing destination...")
    
    # Check if destination already exists
    response = _api_request("destinations/list", {"workspaceId": workspace_id})
    for dest in response.get("destinations", []):
        if dest.get("name") == DESTINATION_NAME:
            dest_id = dest["destinationId"]
            _log(f"  Found existing destination: {dest_id}")
            return dest_id
    
    # Create new destination
    _log("  Creating new destination...")
    response = _api_request("destinations/create", {
        "workspaceId": workspace_id,
        "destinationDefinitionId": POSTGRES_DEST_DEF_ID,
        "connectionConfiguration": DESTINATION_CONFIG,
        "name": DESTINATION_NAME,
    })
    
    dest_id = response["destinationId"]
    _log(f"  ✓ Created destination: {dest_id}")
    return dest_id


# =============================================================================
# SCHEMA DISCOVERY & SYNC CATALOG
# =============================================================================

def discover_schema(source_id: str) -> dict:
    """Discover the source schema (streams available)."""
    _log("→ Discovering source schema...")
    _log("  This may take 30-60 seconds on first run...")
    
    response = _api_request("sources/discover_schema", {
        "sourceId": source_id,
        "disable_cache": True,
    })
    
    catalog = response.get("catalog", {})
    streams = catalog.get("streams", [])
    stream_names = [s["stream"]["name"] for s in streams]
    _log(f"  ✓ Found streams: {', '.join(stream_names)}")
    
    return response


def build_sync_catalog(discovered_schema: dict) -> dict:
    """
    Transform discovered catalog into syncCatalog with all streams enabled.
    
    Uses full_refresh + overwrite for simplicity in POC.
    """
    streams = []
    
    for stream_entry in discovered_schema.get("catalog", {}).get("streams", []):
        stream = stream_entry["stream"]
        streams.append({
            "stream": stream,
            "config": {
                "syncMode": "full_refresh",
                "destinationSyncMode": "overwrite",
                "selected": True,
                "primaryKey": [],
                "cursorField": [],
                "aliasName": stream["name"],
            }
        })
    
    return {"streams": streams}


# =============================================================================
# CONNECTION CREATION
# =============================================================================

def get_or_create_connection(
    workspace_id: str,
    source_id: str,
    destination_id: str,
    sync_catalog: dict
) -> str:
    """Get existing or create new connection."""
    _log("→ Checking for existing connection...")
    
    # Check if connection already exists
    response = _api_request("connections/list", {"workspaceId": workspace_id})
    for conn in response.get("connections", []):
        if (conn.get("sourceId") == source_id and 
            conn.get("destinationId") == destination_id):
            conn_id = conn["connectionId"]
            _log(f"  Found existing connection: {conn_id}")
            return conn_id
    
    # Create new connection
    _log("  Creating new connection...")
    response = _api_request("connections/create", {
        "sourceId": source_id,
        "destinationId": destination_id,
        "syncCatalog": sync_catalog,
        "status": "active",
        "name": CONNECTION_NAME,
        "namespaceDefinition": "destination",
        "namespaceFormat": "${SOURCE_NAMESPACE}",
        "prefix": "_airbyte_raw_",
        "scheduleType": "manual",
        "geography": "auto",
        "nonBreakingChangesPreference": "ignore",
    })
    
    conn_id = response["connectionId"]
    _log(f"  ✓ Created connection: {conn_id}")
    return conn_id


# =============================================================================
# MAIN ORCHESTRATION
# =============================================================================

def main() -> int:
    """
    Main entry point.
    
    Returns:
        0 on success, 1 on failure
    """
    _log("")
    _log("=" * 50)
    _log("  Airbyte Auto-Configuration")
    _log("=" * 50)
    _log("")
    
    try:
        # Step 1: Get workspace
        workspace_id = get_workspace_id()
        
        # Step 2: Create/get source
        source_id = get_or_create_source(workspace_id)
        
        # Step 3: Create/get destination
        destination_id = get_or_create_destination(workspace_id)
        
        # Step 4: Discover schema and build sync catalog
        discovered_schema = discover_schema(source_id)
        sync_catalog = build_sync_catalog(discovered_schema)
        
        # Step 5: Create/get connection
        connection_id = get_or_create_connection(
            workspace_id, source_id, destination_id, sync_catalog
        )
        
        _log("")
        _log("=" * 50)
        _log("  ✓ Configuration Complete!")
        _log("=" * 50)
        _log(f"  Source:      {source_id}")
        _log(f"  Destination: {destination_id}")
        _log(f"  Connection:  {connection_id}")
        _log("")
        
        # Output connection_id to stdout (for setup.sh to capture)
        print(connection_id)
        return 0
        
    except KeyboardInterrupt:
        _log("\n✗ Aborted by user")
        return 1
    except Exception as e:
        _log(f"\n✗ Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
