#!/bin/bash
set -e

# Fix permissions for mounted volumes
mkdir -p /workspace/frappe-bench/logs /workspace/frappe-bench/sites
chown -R frappe:frappe /workspace/frappe-bench/logs /workspace/frappe-bench/sites 2>/dev/null || true

# Install node_modules if missing (needed when apps are mounted as volumes)
# This ensures all services have node_modules available
cd /workspace/frappe-bench
if [ ! -d "apps/frappe/node_modules" ]; then
  echo "Installing node_modules for frappe..."
  gosu frappe bash -c "cd apps/frappe && yarn install"
fi
if [ ! -d "apps/erpnext/node_modules" ]; then
  echo "Installing node_modules for erpnext..."
  gosu frappe bash -c "cd apps/erpnext && yarn install"
fi
if [ -d "apps/synthlane_ims" ] && [ ! -d "apps/synthlane_ims/node_modules" ] && [ -f "apps/synthlane_ims/package.json" ]; then
  echo "Installing node_modules for synthlane_ims..."
  gosu frappe bash -c "cd apps/synthlane_ims && yarn install"
fi

# Execute the command as frappe user
exec gosu frappe "$@"
