FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    build-essential \
    libjpeg-dev \
    libssl-dev \
    libffi-dev \
    libmysqlclient-dev \
    pkg-config \
    xvfb \
    wkhtmltopdf \
    nodejs \
    npm \
    yarn \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /opt/synthlane-bench

# Copy requirements and install Python dependencies
COPY apps/frappe/setup.py apps/frappe/pyproject.toml ./apps/frappe/
COPY apps/erpnext/setup.py apps/erpnext/pyproject.toml ./apps/erpnext/
COPY apps/synthlane_ims/setup.py apps/synthlane_ims/pyproject.toml ./apps/synthlane_ims/

# Install Frappe and apps
RUN pip install --no-cache-dir -e ./apps/frappe -e ./apps/erpnext -e ./apps/synthlane_ims

# Copy application code
COPY . .

# Install Node.js dependencies
RUN cd apps/frappe && yarn install --frozen-lockfile && cd ../../
RUN cd apps/erpnext && yarn install --frozen-lockfile && cd ../../

# Build assets
RUN bench build --force

# Create necessary directories
RUN mkdir -p sites logs

# Set permissions
RUN chmod +x Procfile

# Expose ports
EXPOSE 8000 9000

# Default command
CMD ["bench", "--site", "synthlane.localhost", "serve", "--port", "8000", "--host", "0.0.0.0"]
