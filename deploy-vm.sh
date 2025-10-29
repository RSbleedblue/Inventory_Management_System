#!/bin/bash

# Synthlane IMS VM Deployment Script
# Run this on your VM to deploy the application

set -e

echo "🚀 Synthlane IMS VM Deployment"
echo "=============================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on VM
check_vm() {
    print_status "Checking VM environment..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        print_warning "Please logout and login again, then run this script again."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose not found. Installing..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    print_status "VM environment check passed ✅"
}

# Clone or update repository
setup_repo() {
    print_status "Setting up repository..."
    
    if [ -d "synthlane-bench" ]; then
        print_status "Repository exists, updating..."
        cd synthlane-bench
        git pull origin main
    else
        print_status "Cloning repository..."
        git clone https://github.com/RSbleedblue/Inventory_Management_System.git synthlane-bench
        cd synthlane-bench
    fi
    
    print_status "Repository setup complete ✅"
}

# Setup environment
setup_env() {
    print_status "Setting up environment..."
    
    if [ ! -f ".env" ]; then
        print_warning "Creating .env file..."
        cat > .env << EOF
# Database Configuration
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_DATABASE=synthlane_db
MYSQL_USER=synthlane_user
MYSQL_PASSWORD=$(openssl rand -base64 32)

# Site Configuration
FRAPPE_SITE=synthlane.localhost
DOMAIN_NAME=your-domain.com
EOF
        print_status "Generated secure passwords in .env file"
    else
        print_status "Environment file already exists ✅"
    fi
}

# Deploy services
deploy_services() {
    print_status "Deploying Docker services..."
    
    # Stop existing services
    docker-compose down 2>/dev/null || true
    
    # Build and start services
    docker-compose up -d --build
    
    print_status "Services deployed ✅"
}

# Wait for services
wait_for_services() {
    print_status "Waiting for services to be ready..."
    
    # Wait for MariaDB
    print_status "Waiting for MariaDB..."
    until docker-compose exec mariadb mysqladmin ping -h localhost --silent; do
        sleep 2
    done
    
    # Wait for Redis
    print_status "Waiting for Redis services..."
    until docker-compose exec redis-cache redis-cli ping | grep -q PONG; do
        sleep 2
    done
    
    print_status "All services are ready ✅"
}

# Initialize site
initialize_site() {
    print_status "Initializing site..."
    
    # Wait for backend to be ready
    sleep 10
    
    # Create site
    docker-compose exec backend bench --site synthlane.localhost new-site --mariadb-root-password $(grep MYSQL_ROOT_PASSWORD .env | cut -d '=' -f2) --admin-password admin123
    
    # Install apps
    docker-compose exec backend bench --site synthlane.localhost install-app erpnext
    docker-compose exec backend bench --site synthlane.localhost install-app synthlane_ims
    
    # Build assets
    docker-compose exec backend bench --site synthlane.localhost build
    
    # Clear cache
    docker-compose exec backend bench --site synthlane.localhost clear-cache
    
    print_status "Site initialization complete ✅"
}

# Show status
show_status() {
    print_status "Deployment Status:"
    echo ""
    docker-compose ps
    echo ""
    
    # Get VM IP
    VM_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_VM_IP")
    
    print_status "🎉 Deployment Complete!"
    echo ""
    print_status "Access your application:"
    echo "  🌐 URL: http://$VM_IP"
    echo "  👤 Login: Administrator"
    echo "  🔑 Password: admin123"
    echo ""
    print_warning "Important:"
    echo "  ⚠️  Change the default password after first login"
    echo "  ⚠️  Update DOMAIN_NAME in .env file"
    echo "  ⚠️  Configure SSL certificates for production"
    echo ""
    print_status "Management commands:"
    echo "  📊 Status: docker-compose ps"
    echo "  📝 Logs: docker-compose logs -f"
    echo "  🔄 Restart: docker-compose restart"
    echo "  🛑 Stop: docker-compose down"
}

# Main deployment
main() {
    check_vm
    setup_repo
    setup_env
    deploy_services
    wait_for_services
    initialize_site
    show_status
}

# Run main function
main "$@"
