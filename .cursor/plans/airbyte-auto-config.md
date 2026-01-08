# Airbyte Auto-Configuration Script Plan

## Progress Checklist

- [x] 1. Create Configuration Script (`scripts/configure_airbyte.py`)
- [x] 2. Implement API Helper Layer
- [x] 3. Implement Idempotent Resource Creation
- [x] 4. Implement Schema Discovery & syncCatalog Builder
- [x] 5. Implement Main Orchestration
- [x] 6. Integrate with setup.sh
- [x] 7. Update .gitignore (if needed) — already had Python patterns
- [x] 8. End-to-End Validation — PASSED ✓

---

## Plan Details

### 1. Create Configuration Script `[Risk: Low]`
- Create `scripts/configure_airbyte.py` — single self-contained Python script
- Use stdlib `urllib.request` + `json` (zero external dependencies)
- Define constants matching `copilot-instructions.md`:
  - `AIRBYTE_URL = "http://localhost:8000/api/v1"`
  - `AUTH = ("airbyte", "password")`
  - `FAKER_SOURCE_DEF_ID = "dfd88b22-b603-4c3d-aad7-3701784586b1"`
  - `POSTGRES_DEST_DEF_ID = "25c5221d-dce2-4163-ade9-739ef790f503"`

### 2. Implement API Helper Layer `[Risk: Low]`
- Create `_api_request(endpoint, payload)` wrapper with Basic Auth
- Handle HTTP errors gracefully with clear error messages

### 3. Implement Idempotent Resource Creation `[Risk: Medium]`
- Check-before-create pattern for each resource
- Functions:
  - `get_or_create_source()` — check `/sources/list`, create via `/sources/create`
  - `get_or_create_destination()` — check `/destinations/list`, create via `/destinations/create`
  - `get_or_create_connection()` — check `/connections/list`, create via `/connections/create`

### 4. Implement Schema Discovery & syncCatalog Builder `[Risk: Medium]`
- Call `/sources/discover_schema` after source creation
- Transform discovered catalog → syncCatalog with all streams enabled
- Expected streams: `users`, `products`, `purchases`
- Config: `syncMode: full_refresh`, `destinationSyncMode: overwrite`

### 5. Implement Main Orchestration `[Risk: Low]`
- Sequential flow with progress output
- Exit codes: `0` success, `1` failure
- Print connection_id to stdout for setup.sh capture

### 6. Integrate with setup.sh `[Risk: Low]`
- Add `configure_airbyte()` function after `wait_for_airbyte()`
- Capture connection ID and set Airflow variable
- Call in `main()` when `with_airbyte=true`

### 7. Update .gitignore `[Risk: Low]`
- Verify `__pycache__/` and `*.pyc` entries exist

### 8. End-to-End Validation
- Run `./scripts/setup.sh --clean && ./scripts/setup.sh`
- Verify Airbyte UI shows Source, Destination, Connection
- Verify Airflow variable is set

---

## API Endpoints Used
| Action | Endpoint | Method |
|--------|----------|--------|
| Get workspace | `/workspaces/list` | POST |
| List sources | `/sources/list` | POST |
| Create source | `/sources/create` | POST |
| Discover schema | `/sources/discover_schema` | POST |
| List destinations | `/destinations/list` | POST |
| Create destination | `/destinations/create` | POST |
| List connections | `/connections/list` | POST |
| Create connection | `/connections/create` | POST |
