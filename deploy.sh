#!/bin/bash

set -euo pipefail

# Script metadata
SCRIPT_NAME="deploy.sh"
VERSION="1.0.0"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
GIT_REPO_URL=""
GIT_PAT=""
BRANCH="main"
SSH_USER=""
SERVER_IP=""
SSH_KEY_PATH=""
APP_PORT="3000"
REPO_DIR=""
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Logging functions
setup_logging() {
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
}

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

# Validation functions
validate_git_url() {
    if [[ ! "$1" =~ ^https://.+ ]]; then
        log_error "Invalid Git repository URL format. Must start with https://"
        exit 1
    fi
}

validate_ip() {
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid IP address format"
        exit 1
    fi
}

validate_ssh_key() {
    local key_path="${1/#\~/$HOME}"
    if [ ! -f "$key_path" ]; then
        log_error "SSH key file not found: $key_path"
        exit 1
    fi
}

validate_port() {
    if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        log_error "Invalid port number: $1. Must be between 1-65535"
        exit 1
    fi
}

validate_pat() {
    if [ -z "$1" ]; then
        log_error "Personal Access Token cannot be empty"
        exit 1
    fi
}

# User input collection
collect_user_input() {
    log "Collecting deployment parameters..."
    
    # Git repository details
    while true; do
        read -p "Enter Git Repository URL: " GIT_REPO_URL
        if validate_git_url "$GIT_REPO_URL"; then
            break
        fi
    done
    
    while true; do
        read -s -p "Enter Personal Access Token (PAT): " GIT_PAT
        echo
        if validate_pat "$GIT_PAT"; then
            break
        fi
    done
    
    read -p "Enter branch name [main]: " BRANCH
    BRANCH=${BRANCH:-main}
    
    # SSH details
    read -p "Enter SSH username: " SSH_USER
    if [ -z "$SSH_USER" ]; then
        log_error "SSH username cannot be empty"
        exit 1
    fi
    
    while true; do
        read -p "Enter Server IP address: " SERVER_IP
        if validate_ip "$SERVER_IP"; then
            break
        fi
    done
    
    read -p "Enter SSH key path [~/.ssh/id_rsa]: " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
    validate_ssh_key "$SSH_KEY_PATH"
    
    read -p "Enter application port [3000]: " APP_PORT
    APP_PORT=${APP_PORT:-3000}
    validate_port "$APP_PORT"
    
    log_success "All parameters collected and validated"
}

# Git operations
clone_repository() {
    local repo_name=$(basename "$GIT_REPO_URL" .git)
    local repo_dir="$repo_name"
    
    log "Processing repository: $repo_name"
    
    if [ -d "$repo_dir" ]; then
        log "Repository exists, pulling latest changes..."
        cd "$repo_dir"
        
        # Configure Git for PAT authentication
        git config --local credential.helper 'store --file=.git-credentials'
        echo "https://oauth2:$GIT_PAT@$(echo $GIT_REPO_URL | cut -d'/' -f3-)" > .git-credentials
        
        # Stash any local changes and pull
        git stash push -m "auto-stash-by-deploy-script" || true
        git fetch origin
        git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
        git pull origin "$BRANCH"
        log_success "Repository updated successfully"
    else
        log "Cloning repository..."
        
        # Clone using PAT authentication
        GIT_REPO_WITH_AUTH=$(echo "$GIT_REPO_URL" | sed "s#https://#https://oauth2:${GIT_PAT}@#")
        if git clone -b "$BRANCH" "$GIT_REPO_WITH_AUTH" "$repo_dir" 2>/dev/null || \
           git clone "$GIT_REPO_WITH_AUTH" "$repo_dir"; then
            cd "$repo_dir"
            if [ "$BRANCH" != "main" ]; then
                git checkout "$BRANCH" 2>/dev/null || log_warning "Branch $BRANCH not found, using default branch"
            fi
            log_success "Repository cloned successfully"
        else
            log_error "Failed to clone repository"
            exit 1
        fi
    fi
    
    REPO_DIR=$(pwd)
}

verify_docker_files() {
    log "Verifying Docker configuration files..."
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
        DOCKER_CONFIG="Dockerfile"
    elif [ -f "docker-compose.yml" ]; then
        log_success "docker-compose.yml found"
        DOCKER_CONFIG="compose"
    elif [ -f "docker-compose.yaml" ]; then
        log_success "docker-compose.yaml found"
        DOCKER_CONFIG="compose"
    else
        log_error "No Dockerfile or docker-compose.yml found in repository"
        exit 1
    fi
}

# SSH operations
ssh_command() {
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
        "$SSH_USER@$SERVER_IP" "$1"
}

scp_transfer() {
    local source="$1"
    local destination="$2"
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -r \
        "$source" "$SSH_USER@$SERVER_IP:$destination"
}

test_ssh_connection() {
    log "Testing SSH connection to $SERVER_IP..."
    if ssh_command "echo 'SSH connection successful'"; then
        log_success "SSH connection established"
    else
        log_error "SSH connection failed. Please check credentials and network connectivity"
        exit 1
    fi
}

# Remote server setup
prepare_remote_environment() {
    log "Preparing remote environment on $SERVER_IP..."
    
    local setup_script=$(cat << 'EOF'
#!/bin/bash
set -euo pipefail

log() { echo "$(date): $1"; }
log_success() { echo "✓ $1"; }
log_error() { echo "✗ $1"; }

# Update system packages
log "Updating system packages..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# Install Docker
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    log_success "Docker installed"
else
    log_success "Docker already installed"
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    log "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose installed"
else
    log_success "Docker Compose already installed"
fi

# Install Nginx
if ! command -v nginx &> /dev/null; then
    log "Installing Nginx..."
    sudo apt-get install -y -qq nginx
    log_success "Nginx installed"
else
    log_success "Nginx already installed"
fi

# Start and enable services
sudo systemctl enable docker --now
sudo systemctl enable nginx --now

# Verify installations
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker-compose --version)"
echo "Nginx: $(nginx -v 2>&1)"
EOF
)
    
    ssh_command "$setup_script"
    log_success "Remote environment prepared"
}

# Application deployment
deploy_application() {
    log "Deploying application to remote server..."
    
    local remote_project_dir="/home/$SSH_USER/$(basename "$REPO_DIR")"
    local project_name=$(basename "$REPO_DIR")
    
    # Transfer project files
    log "Transferring project files to remote server..."
    if scp_transfer "$REPO_DIR" "/home/$SSH_USER/"; then
        log_success "Project files transferred"
    else
        log_error "Failed to transfer project files"
        exit 1
    fi
    
    local deploy_script=$(cat << EOF
#!/bin/bash
set -euo pipefail

cd "$remote_project_dir"

log() { echo "$(date): $1"; }
log_error() { echo "✗ $1"; }

# Stop and remove existing containers
log "Stopping any existing containers..."
docker-compose down 2>/dev/null || true
docker stop app_container 2>/dev/null || true
docker rm app_container 2>/dev/null || true

# Build and run based on configuration
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    log "Using Docker Compose for deployment..."
    docker-compose up -d --build
    log "Waiting for containers to be healthy..."
    sleep 15
    
    # Check container status
    if docker-compose ps | grep -q "Up"; then
        log "Docker Compose containers are running"
    else
        log_error "Docker Compose containers failed to start"
        docker-compose logs
        exit 1
    fi
elif [ -f "Dockerfile" ]; then
    log "Using Dockerfile for deployment..."
    docker build -t ${project_name}_image .
    docker run -d --name app_container -p $APP_PORT:$APP_PORT ${project_name}_image
    sleep 10
    
    # Check container status
    if docker ps | grep -q "app_container"; then
        log "Docker container is running"
    else
        log_error "Docker container failed to start"
        docker logs app_container
        exit 1
    fi
else
    log_error "No Docker configuration found"
    exit 1
fi

# Verify application is running
log "Verifying application health..."
if curl -f -s -o /dev/null --retry 3 --retry-delay 5 http://localhost:$APP_PORT; then
    log "Application is healthy and responding"
else
    log_error "Application health check failed"
    exit 1
fi
EOF
)
    
    ssh_command "$deploy_script"
    log_success "Application deployed successfully"
}

# Nginx configuration
configure_nginx() {
    log "Configuring Nginx reverse proxy..."
    
    local nginx_config=$(cat << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }
    
    # Block common exploits
    location ~* (\.env|\.git|\.htaccess) {
        deny all;
        return 404;
    }
}
EOF
)
    
    local nginx_setup=$(cat << EOF
#!/bin/bash
set -euo pipefail

# Create nginx config
echo '$nginx_config' | sudo tee /etc/nginx/sites-available/app > /dev/null

# Enable site
sudo ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "Nginx configuration validated and reloaded"
else
    echo "Nginx configuration test failed"
    exit 1
fi
EOF
)
    
    ssh_command "$nginx_setup"
    log_success "Nginx reverse proxy configured"
}

# Deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    local validation_script=$(cat << 'EOF'
#!/bin/bash
set -euo pipefail

log() { echo "$(date): $1"; }
log_error() { echo "✗ $1"; }

# Check Docker service
if ! systemctl is-active --quiet docker; then
    log_error "Docker service is not running"
    exit 1
fi
log "Docker service is running"

# Check containers
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    if docker-compose ps | grep -q "Up"; then
        log "Docker Compose containers are running"
    else
        log_error "Docker Compose containers are not running"
        exit 1
    fi
else
    if docker ps | grep -q "app_container"; then
        log "Docker container is running"
    else
        log_error "Docker container is not running"
        exit 1
    fi
fi

# Check Nginx
if ! systemctl is-active --quiet nginx; then
    log_error "Nginx is not running"
    exit 1
fi
log "Nginx service is running"

# Test application directly
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:$APP_PORT | grep -q "200"; then
    log "Application is responding on port $APP_PORT"
else
    log_error "Application is not responding on port $APP_PORT"
    exit 1
fi

# Test Nginx proxy
if curl -f -s -o /dev/null -w "%{http_code}" http://localhost; then
    log "Nginx proxy is working correctly"
else
    log_error "Nginx proxy is not working"
    exit 1
fi

# Final end-to-end test from external perspective
if curl -f -s -o /dev/null http://localhost/health 2>/dev/null || \
   curl -f -s -o /dev/null http://localhost/ 2>/dev/null || \
   curl -f -s -o /dev/null http://localhost; then
    log "End-to-end deployment validation successful"
else
    log_error "End-to-end deployment validation failed"
    exit 1
fi
EOF
)
    
    local remote_project_dir="/home/$SSH_USER/$(basename "$REPO_DIR")"
    if ssh_command "cd $remote_project_dir && $validation_script"; then
        log_success "Deployment validation successful"
    else
        log_error "Deployment validation failed"
        exit 1
    fi
}

# Cleanup function
cleanup_resources() {
    log "Starting cleanup of deployment resources..."
    
    local cleanup_script=$(cat << EOF
#!/bin/bash
set -euo pipefail

log() { echo "$(date): $1"; }

local_project_dir="/home/$SSH_USER/$(basename "$REPO_DIR")"

if [ -d "\$local_project_dir" ]; then
    cd "\$local_project_dir"
    log "Stopping and removing containers..."
    docker-compose down 2>/dev/null || true
    docker stop app_container 2>/dev/null || true
    docker rm app_container 2>/dev/null || true
    docker rmi \$(basename "$REPO_DIR")_image 2>/dev/null || true
    
    log "Removing project files..."
    cd ..
    rm -rf "\$(basename "$REPO_DIR")"
fi

log "Cleaning up Nginx configuration..."
sudo rm -f /etc/nginx/sites-available/app
sudo rm -f /etc/nginx/sites-enabled/app
sudo systemctl reload nginx

log "Cleanup completed"
EOF
)
    
    ssh_command "$cleanup_script"
    log_success "Cleanup completed successfully"
}

# Display deployment info
show_deployment_info() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo "Application Information:"
    echo "-----------------------"
    echo "URL: http://$SERVER_IP"
    echo "App Port: $APP_PORT"
    echo "Server: $SSH_USER@$SERVER_IP"
    echo "Project: $(basename "$REPO_DIR")"
    echo "Log File: $LOG_FILE"
    echo
    echo "Next steps:"
    echo "1. Test the application at: http://$SERVER_IP"
    echo "2. Check logs if needed: $LOG_FILE"
    echo "3. To cleanup, run: $0 --cleanup"
    echo
}

# Main deployment function
run_deployment() {
    log "Starting automated deployment process..."
    
    collect_user_input
    test_ssh_connection
    clone_repository
    verify_docker_files
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    show_deployment_info
}

# Cleanup only function
run_cleanup() {
    log "Starting cleanup process..."
    collect_user_input
    test_ssh_connection
    cleanup_resources
    log_success "Cleanup completed"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTION]

Automated Deployment Script for Dockerized Applications

Options:
    --cleanup    Remove all deployed resources from the server
    --help       Show this help message
    --version    Show version information

Without options, runs the full deployment process.

Features:
- Automated Git repository cloning with PAT authentication
- Remote server provisioning (Docker, Docker Compose, Nginx)
- Docker container deployment and management
- Nginx reverse proxy configuration
- Comprehensive logging and validation

Example:
  $0          # Run full deployment
  $0 --cleanup # Remove deployed resources

EOF
}

# Version function
show_version() {
    echo "$SCRIPT_NAME version $VERSION"
    echo "Production-grade automated deployment script"
}

# Main execution
main() {
    setup_logging
    
    case "${1:-}" in
        --cleanup)
            run_cleanup
            ;;
        --help|-h)
            show_help
            ;;
        --version|-v)
            show_version
            ;;
        "")
            run_deployment
            ;;
        *)
            log_error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'log_error "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"