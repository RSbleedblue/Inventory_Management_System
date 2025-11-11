FROM frappe/bench:latest

USER root

# Install additional dependencies
RUN apt-get update && apt-get install -y \
    mariadb-client \
    redis-tools \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Initialize a new bench
WORKDIR /workspace
RUN chown -R frappe:frappe /workspace

USER frappe

# Initialize bench
RUN bench init --skip-redis-config-generation --frappe-branch version-15 frappe-bench

WORKDIR /workspace/frappe-bench

# Copy apps into the bench
COPY --chown=frappe:frappe apps/frappe /workspace/frappe-bench/apps/frappe
COPY --chown=frappe:frappe apps/erpnext /workspace/frappe-bench/apps/erpnext  
COPY --chown=frappe:frappe apps/synthlane_ims /workspace/frappe-bench/apps/synthlane_ims

# Install the apps into the bench virtual environment
RUN ./env/bin/pip install --no-cache-dir -e ./apps/frappe && \
    ./env/bin/pip install --no-cache-dir -e ./apps/erpnext && \
    ./env/bin/pip install --no-cache-dir -e ./apps/synthlane_ims

# Install node dependencies
RUN cd apps/frappe && yarn install && \
    cd ../erpnext && yarn install

# Register apps with bench
RUN printf "frappe\nerpnext\nsynthlane_ims\n" > sites/apps.txt

# Build assets for all apps
RUN bench build

# Copy startup script
USER root
COPY docker-entrypoint.sh /usr/local/bin/
COPY start.sh /workspace/frappe-bench/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /workspace/frappe-bench/start.sh && \
    chown frappe:frappe /workspace/frappe-bench/start.sh

# Create directories and fix permissions
RUN mkdir -p /workspace/frappe-bench/logs /workspace/frappe-bench/sites && \
    chown -R frappe:frappe /workspace/frappe-bench

# Expose ports
EXPOSE 8000 9000

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command
CMD ["/workspace/frappe-bench/start.sh"]
