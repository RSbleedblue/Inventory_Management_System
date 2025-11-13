# Hot Reload Setup for Frappe/ERPNext Development

This document explains how we set up hot-reloading for both frontend assets (JS/CSS) and backend JSON configuration files (DocTypes, Onboarding Steps, etc.) in a Docker-based Frappe/ERPNext development environment.

## Problem Statement

When developing in Frappe/ERPNext with Docker, making changes to code files required:
1. **Frontend changes (JS/CSS)**: Manual rebuild and container restart
2. **Backend JSON files (DocTypes, Onboarding Steps)**: Changes only reflected after creating a new site, not on existing sites

This made development slow and inefficient, especially when working with JSON configuration files like Onboarding Steps.

## Solution Overview

We implemented a comprehensive hot-reloading solution that includes:

1. **Volume Mounting**: Mount app directories as volumes so changes are reflected in containers
2. **Asset Watcher**: Automatic rebuild of frontend assets when JS/CSS files change
3. **JSON Reload Watcher**: Automatic reload of JSON DocType files when they change
4. **Developer Mode**: Enabled to bypass caching and ensure changes are always applied
5. **Cache Management**: Aggressive cache clearing to ensure fresh data

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose Setup                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   Backend    │  │     Watch    │  │ Reload       │    │
│  │   Service    │  │   Service    │  │ Watcher      │    │
│  │              │  │              │  │              │    │
│  │ - Serves app │  │ - Watches    │  │ - Watches    │    │
│  │ - Dev mode   │  │   JS/CSS     │  │   JSON files │    │
│  │   enabled    │  │ - Auto build │  │ - Auto reload│    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                  │                  │             │
│         └──────────────────┴──────────────────┘           │
│                            │                               │
│                   ┌────────▼────────┐                      │
│                   │  Volume Mounts │                      │
│                   │  ./apps/*       │                      │
│                   └─────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. Volume Mounting for Hot-Reloading

**File**: `docker-compose.yml`

All services that need access to code changes have the app directories mounted as volumes:

```yaml
volumes:
  - sites_data:/workspace/frappe-bench/sites
  - logs_data:/workspace/frappe-bench/logs
  # Mount apps for hot-reloading
  - ./apps/frappe:/workspace/frappe-bench/apps/frappe
  - ./apps/erpnext:/workspace/frappe-bench/apps/erpnext
  - ./apps/synthlane_ims:/workspace/frappe-bench/apps/synthlane_ims
```

**Why**: This ensures that when you edit files on your host machine, the changes are immediately visible inside the Docker containers.

### 2. Developer Mode Configuration

**File**: `start.sh`

```bash
"developer_mode": true,
```

**Why**: Developer mode:
- Disables aggressive caching
- Enables faster builds
- Allows JSON files to be reloaded even when timestamps suggest no changes
- Provides better error messages

### 3. Asset Watcher Service

**File**: `docker-compose.yml` - `watch` service

```yaml
watch:
  command: ["bash", "-c", "cd /workspace/frappe-bench && exec bench watch"]
```

**What it does**:
- Watches for changes in JS/CSS/Vue files
- Automatically rebuilds assets using `bench watch`
- Sends build events to the frontend for hot-reloading

**How it works**:
- Uses Frappe's built-in `bench watch` command
- Monitors files in `apps/*/public/js/`, `apps/*/public/css/`, etc.
- Rebuilds only changed files
- Notifies frontend via Redis/SocketIO

### 4. JSON Reload Watcher Service

**File**: `reload-doc-watcher.py` + `docker-compose.yml` - `reload-watcher` service

**What it does**:
- Watches for changes in JSON DocType files (e.g., Onboarding Step JSON files)
- Automatically runs `bench reload-doc` when JSON files change
- Updates the `modified` timestamp in JSON files to ensure reload happens
- Clears cache after reloading

**Key Features**:

1. **Automatic Timestamp Update**:
   ```python
   def update_json_timestamp(self, file_path):
       # Updates the 'modified' field in JSON to current time
       # This ensures Frappe recognizes the file as changed
   ```

2. **Force Reload with Cache Clearing**:
   ```python
   def reload_doc(self, module, doctype, docname):
       # Runs: bench --site <site> reload-doc <module> <doctype> <docname> --force
       # Then: bench --site <site> clear-cache
   ```

3. **File Pattern Detection**:
   - Detects JSON files matching pattern: `apps/{app}/{app}/{module}/{doctype}/{name}/{name}.json`
   - Example: `apps/erpnext/erpnext/accounts/onboarding_step/setup_taxes/setup_taxes.json`

### 5. Developer Mode Bypass for Onboarding Steps

**File**: `apps/frappe/frappe/modules/import_file.py`

**Problem**: Frappe's import logic skips reloading if:
- Database timestamp is newer than JSON file timestamp
- Hash matches (suggesting no changes)

**Solution**: In developer mode, always reload Onboarding Step documents:

```python
# For Onboarding Step in developer mode, always reload regardless of timestamps/hash
if doc.get("doctype") == "Onboarding Step" and frappe.conf.developer_mode:
    should_skip = False  # Never skip in developer mode
```

**Why**: This ensures that during development, JSON changes are always applied, even if Frappe's normal logic would skip them.

### 6. Aggressive Cache Clearing

**Multiple locations**:

1. **After JSON Import** (`import_file.py`):
   ```python
   if doc.doctype == "Onboarding Step":
       frappe.clear_cache(doctype="Onboarding Step")
       frappe.cache.delete_value(f"document_cache::{doc.doctype}::{doc.name}")
   ```

2. **In get_onboarding_steps()** (`onboarding_step.py`):
   ```python
   frappe.clear_cache(doctype="Onboarding Step")
   frappe.cache.delete_value(f"document_cache::Onboarding Step::{step_name}")
   frappe.db.clear_cache()
   ```

3. **After Reload Watcher** (`reload-doc-watcher.py`):
   ```python
   subprocess.run(["bench", "--site", SITE_NAME, "clear-cache"])
   ```

**Why**: Frappe caches documents in multiple places (Redis, local cache, database cache). We clear all of them to ensure fresh data.

## File Structure

```
Inventory_Management_System/
├── docker-compose.yml          # Docker services configuration
├── Dockerfile                  # Container build instructions
├── start.sh                    # Backend startup script
├── docker-entrypoint.sh        # Container entrypoint
├── reload-doc-watcher.py       # JSON file watcher service
├── apps/
│   ├── frappe/                 # Frappe framework
│   ├── erpnext/                # ERPNext app
│   └── synthlane_ims/          # Custom app
└── HOT_RELOAD_SETUP.md         # This documentation
```

## How to Use

### Starting the Development Environment

```bash
# Build and start all services
docker-compose up -d

# Watch logs
docker-compose logs -f backend watch reload-watcher
```

### Making Frontend Changes

1. Edit JS/CSS/Vue files in `apps/*/public/`
2. The `watch` service automatically rebuilds assets
3. Refresh browser (hard refresh: Ctrl+Shift+R / Cmd+Shift+R)

### Making Backend JSON Changes

1. Edit JSON files in `apps/*/{app}/{module}/{doctype}/{name}/{name}.json`
2. The `reload-watcher` service automatically:
   - Updates the `modified` timestamp in the JSON file
   - Runs `bench reload-doc --force`
   - Clears cache
3. Refresh browser to see changes

### Example: Changing Onboarding Step Description

**File**: `apps/erpnext/erpnext/accounts/onboarding_step/chart_of_accounts/chart_of_accounts.json`

```json
{
  "description": "# Chart Of Accounts\n\nYOUR NEW CUSTOM TEXT HERE",
  ...
}
```

**What happens**:
1. File is saved
2. `reload-watcher` detects change
3. Updates `modified` timestamp
4. Runs: `bench --site synthlane.localhost reload-doc accounts onboarding_step "Chart of Accounts" --force`
5. Clears cache
6. Changes appear in browser after refresh

## Debugging

### Check if Watchers are Running

```bash
# Check reload-watcher logs
docker-compose logs reload-watcher

# Check asset watcher logs
docker-compose logs watch

# Check backend logs for debug output
docker-compose logs backend | grep DEBUG
```

### Expected Log Output

**When JSON file changes**:
```
[Reload Watcher] Detected change in chart_of_accounts.json
[Reload Watcher] ✓ Updated modified timestamp in JSON to: 2024-01-15 10:30:45.123456
[Reload Watcher] Running: bench --site synthlane.localhost reload-doc accounts onboarding_step Chart of Accounts --force
[Reload Watcher] ✓ Successfully reloaded onboarding_step > Chart of Accounts
[Reload Watcher] Clearing cache...
[Reload Watcher] ✓ Cache cleared successfully

[DEBUG] 🔄 Developer mode: Forcing reload for Onboarding Step
[DEBUG] 💾 Inserting Onboarding Step into database: Chart of Accounts
[DEBUG] ✨ Onboarding Step inserted successfully: Chart of Accounts
[DEBUG] 🧹 Clearing cache for Onboarding Step: Chart of Accounts
```

**When frontend file changes**:
```
[Watch] Detected change in some_file.js
[Watch] Rebuilding assets...
[Watch] ✓ Build complete
```

### Troubleshooting

#### Changes Not Reflecting

1. **Check if watcher is running**:
   ```bash
   docker-compose ps | grep -E "watch|reload"
   ```

2. **Check logs for errors**:
   ```bash
   docker-compose logs reload-watcher | tail -50
   ```

3. **Verify file is being watched**:
   - Check that file path matches pattern: `apps/{app}/{app}/{module}/{doctype}/{name}/{name}.json`
   - Check that app is in `APPS_TO_WATCH` list in `reload-doc-watcher.py`

4. **Manual reload** (if auto-reload fails):
   ```bash
   docker-compose exec backend bench --site synthlane.localhost reload-doc accounts onboarding_step "Chart of Accounts" --force
   docker-compose exec backend bench --site synthlane.localhost clear-cache
   ```

5. **Clear browser cache**:
   - Hard refresh: Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac)
   - Or clear browser cache completely

#### Reload Watcher Not Detecting Changes

1. **Check file permissions**:
   ```bash
   ls -la apps/erpnext/erpnext/accounts/onboarding_step/chart_of_accounts/
   ```

2. **Verify volume mount**:
   ```bash
   docker-compose exec backend ls -la /workspace/frappe-bench/apps/erpnext/erpnext/accounts/onboarding_step/
   ```

3. **Check if watchdog is installed**:
   ```bash
   docker-compose exec backend python3 -c "import watchdog; print('OK')"
   ```

#### Cache Issues

If changes still don't appear after reload:

1. **Clear all caches manually**:
   ```bash
   docker-compose exec backend bench --site synthlane.localhost clear-cache
   docker-compose exec backend bench --site synthlane.localhost clear-website-cache
   ```

2. **Restart backend**:
   ```bash
   docker-compose restart backend
   ```

## Key Configuration Files

### docker-compose.yml

- **Volume mounts**: Enable hot-reloading by mounting app directories
- **Environment variables**: `PYTHONUNBUFFERED=1` for immediate log output
- **Services**: `watch` (frontend), `reload-watcher` (backend JSON)

### start.sh

- Sets `developer_mode: true`
- Installs node_modules if missing (for mounted volumes)
- Starts Frappe server

### reload-doc-watcher.py

- Watches JSON files using `watchdog`
- Updates JSON timestamps automatically
- Runs `bench reload-doc --force`
- Clears cache after reload

### import_file.py (Modified)

- Bypasses timestamp/hash checks for Onboarding Steps in developer mode
- Always reloads Onboarding Steps when `developer_mode=True`
- Clears cache after import

## Technical Details

### Why JSON Files Need Special Handling

Frappe uses several mechanisms to avoid unnecessary reloads:

1. **Timestamp Comparison**: If DB timestamp is newer than JSON, skip reload
2. **Hash Comparison**: If file hash matches stored hash, skip reload
3. **Caching**: Documents are cached in Redis and local memory

Our solution:
- Updates JSON timestamp when file changes (ensures timestamp check passes)
- Uses `--force` flag (bypasses hash check)
- Developer mode bypass (always reloads Onboarding Steps)
- Aggressive cache clearing (ensures fresh data)

### Why Frontend Assets Work Differently

Frontend assets (JS/CSS) are:
- Built into bundles by esbuild
- Served as static files
- Automatically rebuilt by `bench watch`
- Hot-reloaded via SocketIO events

JSON files are:
- Stored in database
- Cached in multiple layers
- Require explicit reload via `bench reload-doc`
- Need cache clearing to show changes

## Best Practices

1. **Always use developer mode** during development
2. **Watch the logs** to verify changes are being detected and reloaded
3. **Hard refresh browser** after making changes
4. **Check logs first** if changes don't appear
5. **Use the debug prints** to trace where documents are loaded

## Limitations

1. **Node modules**: Must be installed in mounted directories (handled automatically)
2. **First load**: May take time to install dependencies
3. **Browser cache**: May need hard refresh
4. **Database changes**: Some changes (like DocType schema) may require migration

## Future Improvements

Potential enhancements:
1. Watch for Python file changes and auto-reload
2. Watch for DocType JSON changes (currently only Onboarding Steps)
3. Better error handling and retry logic
4. Webhook-based reloading for remote development
5. Selective cache clearing (only affected doctypes)

## Summary

We've implemented a comprehensive hot-reloading solution that:

✅ **Frontend**: Automatic rebuild of JS/CSS when files change  
✅ **Backend JSON**: Automatic reload of Onboarding Step JSON files  
✅ **Developer Mode**: Bypasses caching to ensure changes are always applied  
✅ **Cache Management**: Aggressive clearing to ensure fresh data  
✅ **Debug Logging**: Comprehensive logging to track the reload process  

This makes development significantly faster and more efficient, allowing you to see changes immediately without manual rebuilds or site recreation.

