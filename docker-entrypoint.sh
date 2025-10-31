#!/bin/bash
set -e

# Fix permissions for mounted volumes
mkdir -p /workspace/frappe-bench/logs /workspace/frappe-bench/sites
chown -R frappe:frappe /workspace/frappe-bench/logs /workspace/frappe-bench/sites 2>/dev/null || true

# Execute the command as frappe user
exec gosu frappe "$@"
