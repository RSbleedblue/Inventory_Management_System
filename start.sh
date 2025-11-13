#!/bin/bash
set -e

# Ensure Python output is unbuffered for Docker logs
export PYTHONUNBUFFERED=1

cd /workspace/frappe-bench

# Update common_site_config.json with Docker settings
cat > sites/common_site_config.json <<EOF
{
 "background_workers": 1,
 "db_host": "mariadb",
 "db_port": "3306",
 "db_type": "mariadb",
 "developer_mode": true,
 "gunicorn_workers": 4,
 "redis_cache": "redis://redis-cache:6379",
 "redis_queue": "redis://redis-queue:6379",
 "redis_socketio": "redis://redis-socketio:6379",
 "serve_default_site": true,
 "socketio_port": 9000,
 "webserver_port": 8000
}
EOF

# Create site if it doesn't exist
if [ ! -d sites/synthlane.localhost ]; then
  echo "Creating new site: synthlane.localhost"
  bench new-site synthlane.localhost \
    --mariadb-root-password ${MYSQL_ROOT_PASSWORD:-synthlane_root_pass} \
    --admin-password ${ADMIN_PASSWORD:-admin} \
    --no-mariadb-socket \
    --force
  
  echo "Installing erpnext..."
  bench --site synthlane.localhost install-app erpnext
  
  echo "Installing synthlane_ims..."
  bench --site synthlane.localhost install-app synthlane_ims
fi

# Run migrations
echo "Running migrations..."
bench --site synthlane.localhost migrate

# Install node_modules if missing (needed when apps are mounted as volumes)
echo "Checking node_modules..."
if [ ! -d "apps/frappe/node_modules" ]; then
  echo "Installing node_modules for frappe..."
  cd apps/frappe && yarn install && cd ../..
fi
if [ ! -d "apps/erpnext/node_modules" ]; then
  echo "Installing node_modules for erpnext..."
  cd apps/erpnext && yarn install && cd ../..
fi
if [ -d "apps/synthlane_ims" ] && [ ! -d "apps/synthlane_ims/node_modules" ] && [ -f "apps/synthlane_ims/package.json" ]; then
  echo "Installing node_modules for synthlane_ims..."
  cd apps/synthlane_ims && yarn install && cd ../..
fi

# Clear cache
echo "Clearing cache..."
bench --site synthlane.localhost clear-cache

# Start the application
echo "Starting Frappe..."
exec bench serve --port 8000

