#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="https://github.com/tuyijmv/REB-ELEARNING-OPTIMISATION.git"
INSTALL_DIR="/opt/reb-elearning-optimisation"
SCRIPT_VERSION="1.0.0"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    log_info "Detected OS: $OS $VER"
}

install_docker() {
    if command_exists docker; then
        log_success "Docker already installed ($(docker --version))"
        return 0
    fi
    log_info "Installing Docker..."
    
    if [ "$OS" == "ubuntu" ]; then
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release
        
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VER stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker
    else
        log_error "Unsupported OS: $OS. Please install Docker manually."
        exit 1
    fi
    
    log_success "Docker installed successfully."
}

install_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command_exists git; then
        log_info "Installing git..."
        apt-get install -y -qq git
    fi
    
    if ! command_exists jq; then
        log_info "Installing jq..."
        apt-get install -y -qq jq
    fi
    
    if ! command_exists curl; then
        log_info "Installing curl..."
        apt-get install -y -qq curl
    fi
    
    log_success "All dependencies satisfied."
}

find_free_port() {
    for port in $(seq 8080 8090); do
        if ! (echo > /dev/tcp/localhost/$port) >/dev/null 2>&1; then
            echo $port
            return
        fi
    done
    echo 8080
}

setup_local() {
    MODE="local"
    log_info "=== REB E-Learning Optimisation - Local Docker Mode ==="
    log_info "Version: $SCRIPT_VERSION"
    
    detect_os
    install_dependencies
    install_docker
    
    # Clone repository if not already present
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log_info "Cloning REB E-Learning Optimisation to $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        log_info "Repository already exists at $INSTALL_DIR. Pulling latest..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard origin/main
    fi
    
    cd "$INSTALL_DIR"
    
    # Setup .env
    if [ ! -f ".env" ]; then
        log_info "Setting up .env file..."
        cp .env.example .env
        
        # Find free port
        HOST_PORT=$(find_free_port)
        log_info "Auto-selected host port: $HOST_PORT"
        
        # Update .env with auto-selected port and DB settings
        if command_exists sed; then
            sed -i "s/^MOODLE_PORT=.*/MOODLE_PORT=$HOST_PORT/" .env
            sed -i "s/^MOODLE_WWWROOT=.*/MOODLE_WWWROOT=http:\/\/localhost:$HOST_PORT/" .env
            sed -i "s/^DB_TYPE=.*/DB_TYPE=mysqli/" .env
            sed -i "s/^DB_HOST=.*/DB_HOST=moodle_mysql/" .env
            sed -i "s/^DB_NAME=.*/DB_NAME=moodle/" .env
            sed -i "s/^DB_USER=.*/DB_USER=moodleuser/" .env
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=moodlepass/" .env
            sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=rootpass/" .env
        fi
        
        log_success ".env configured with port $HOST_PORT"
    else
        log_info ".env already exists, skipping configuration."
    fi
    
    # Build Moodle
    log_info "Building Moodle application..."
    ./build.sh
    
    # Start Docker Compose
    log_info "Starting Docker Compose services..."
    docker compose up -d
    
    # Wait for MySQL to be healthy
    log_info "Waiting for MySQL to be healthy..."
    for i in $(seq 1 60); do
        if docker compose ps | grep -q "mysql.*healthy"; then
            log_success "MySQL is healthy."
            break
        fi
        sleep 5
        if [ "$i" -eq 60 ]; then
            log_warn "MySQL health check timeout. Continuing anyway..."
        fi
    done
    
    # Install Composer dependencies
    log_info "Running composer install..."
    docker compose exec -T php composer install -d /var/www/html/moodle_app || true
    
    # Wait for PHP container to be ready
    sleep 5
    
    # Run Moodle CLI installer if config.php is missing
    if ! docker compose exec -T php test -f /var/www/html/moodle_app/config.php 2>/dev/null; then
        log_info "Running Moodle CLI installer..."
        MOODLE_WWWROOT=$(grep MOODLE_WWWROOT .env | cut -d= -f2)
        DB_TYPE=$(grep DB_TYPE .env | cut -d= -f2)
        DB_NAME=$(grep DB_NAME .env | cut -d= -f2)
        DB_USER=$(grep DB_USER .env | cut -d= -f2)
        DB_PASS=$(grep DB_PASSWORD .env | cut -d= -f2)
        DB_HOST=$(grep DB_HOST .env | cut -d= -f2)
        DB_PORT=$(grep DB_PORT .env | cut -d= -f2)
        
        docker compose exec -T php php /var/www/html/moodle_app/admin/cli/install.php \
            --wwwroot="$MOODLE_WWWROOT" \
            --dbtype="$DB_TYPE" \
            --dbname="$DB_NAME" \
            --dbuser="$DB_USER" \
            --dbpass="$DB_PASS" \
            --dbhost="$DB_HOST" \
            --dbport="$DB_PORT" \
            --prefix=mdl_ \
            --fullname="REB E-Learning Optimisation" \
            --shortname="REB E-Learning" \
            --adminuser=admin \
            --adminpass="admin@123" \
            --adminemail="admin@example.com" \
            --non-interactive \
            --agree-license
        
        log_success "Moodle installed successfully."
    else
        log_info "Moodle already configured (config.php exists). Skipping installer."
    fi
    
    # Append reverse proxy settings to config.php
    if docker compose exec -T php test -f /var/www/html/moodle_app/config.php 2>/dev/null; then
        log_info "Updating config.php proxy settings..."
        docker compose exec -T php bash -c "echo '' >> /var/www/html/moodle_app/config.php && echo '\$CFG->reverseproxy = false;' >> /var/www/html/moodle_app/config.php && echo '\$CFG->sslproxy = false;' >> /var/www/html/moodle_app/config.php"
    fi
    
    # Ensure Redis session settings are in config.php
    log_info "Configuring Redis session settings..."
    docker compose exec -T php bash -c "cat >> /var/www/html/moodle_app/config.php << 'EOF2'

\$CFG->session_redis_host = 'redis';
\$CFG->session_redis_port = 6379;
\$CFG->session_redis_database = 0;
\$CFG->session_redis_prefix = 'moodle_session_';
EOF2"
    
    log_success "=============================================="
    log_success "REB E-Learning Optimisation is ready!"
    log_success "=============================================="
    echo ""
    echo -e "  URL:      ${GREEN}http://localhost:$HOST_PORT${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}admin@123${NC}"
    echo ""
    echo "Management commands:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose logs -f          # View logs"
    echo "  docker compose restart          # Restart services"
    echo "  docker compose down             # Stop services"
    echo "  docker compose up -d            # Start services"
    echo ""
}

setup_cloud() {
    MODE="cloud"
    log_info "=== REB E-Learning Optimisation - Cloud Mode ==="
    log_info "Version: $SCRIPT_VERSION"
    
    echo ""
    echo "Cloud mode will provision:"
    echo "  - AWS/GCP/Azure VPC and networking"
    echo "  - Auto-scaling application servers"
    echo "  - Managed MySQL 8.4 (RDS/Aurora)"
    echo "  - ElastiCache Redis cluster"
    echo "  - S3/Cloud Storage for moodledata"
    echo "  - Load balancer with SSL"
    echo "  - CDN (CloudFront/Cloud CDN)"
    echo "  - Monitoring (Prometheus/Grafana)"
    echo "  - CI/CD pipeline"
    echo ""
    
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log_info "Cloning REB E-Learning Optimisation to $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        cd "$INSTALL_DIR"
    fi
    
    cd "$INSTALL_DIR"
    
    echo "Cloud provisioning options:"
    echo ""
    PS3="Select cloud provider: "
    options=("AWS" "Google Cloud" "Azure" "Cancel")
    select opt in "${options[@]}"; do
        case $REPLY in
            1) CLOUD_PROVIDER="aws"; break ;;
            2) CLOUD_PROVIDER="gcp"; break ;;
            3) CLOUD_PROVIDER="azure"; break ;;
            4) log_info "Cancelled."; exit 0 ;;
            *) log_error "Invalid option";;
        esac
    done
    
    echo ""
    read -p "Enter environment name [prod]: " ENV_NAME
    ENV_NAME=${ENV_NAME:-prod}
    
    read -p "Enter AWS region [eu-west-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-eu-west-1}
    
    read -p "Enter domain name: " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "Domain name is required for cloud deployment."
        exit 1
    fi
    
    read -p "Enter email for SSL certificate: " SSL_EMAIL
    
    log_info "Initialising Terraform..."
    cd terraform
    
    cp terraform.tfvars.example terraform.tfvars
    sed -i "s/environment = \"prod\"/environment = \"$ENV_NAME\"/" terraform.tfvars
    sed -i "s/domain_name = \"example.com\"/domain_name = \"$DOMAIN_NAME\"/" terraform.tfvars
    sed -i "s/ssl_email = \"admin@example.com\"/ssl_email = \"$SSL_EMAIL\"/" terraform.tfvars
    
    log_info "Run 'cd terraform && terraform plan' to preview changes."
    log_info "Run 'cd terraform && terraform apply' to deploy."
    log_info ""
    log_info "After infrastructure is ready, run Ansible:"
    log_info "  cd ansible && ansible-playbook -i inventory playbook.yml"
}

usage() {
    echo "REB E-Learning Optimisation Installer v$SCRIPT_VERSION"
    echo ""
    echo "Usage:"
    echo "  reb --local              Deploy local Docker stack"
    echo "  reb --cloud              Provision cloud infrastructure"
    echo "  reb --version            Show version"
    echo "  reb --help               Show this help"
    echo ""
    echo "Local deployment installs:"
    echo "  - Docker & docker-compose plugin"
    echo "  - Moodle 5.1 with MySQL 8.4"
    echo "  - Nginx + PHP-FPM + Redis + MinIO"
    echo "  - Admin credentials: admin / admin@123"
    echo ""
    echo "Cloud deployment provisions:"
    echo "  - Auto-scaling EC2/GCE/Azure VMs"
    echo "  - Managed databases with HA"
    echo "  - Load balancer + CDN + SSL"
    echo "  - Prometheus + Grafana monitoring"
    echo ""
}

# Main entry point
case "${1:-}" in
    --local)
        setup_local
        ;;
    --cloud)
        setup_cloud
        ;;
    --version|-v)
        echo "REB E-Learning Optimisation Installer v$SCRIPT_VERSION"
        ;;
    --help|-h)
        usage
        ;;
    "")
        log_error "No mode specified."
        usage
        exit 1
        ;;
    *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac
