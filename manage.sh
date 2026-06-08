#!/bin/bash

# Docker Management Script for OpenMRS Reference Application
# Provides interactive menu for common Docker operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to build containers
build_containers() {
    print_header "Building Containers"
    docker compose build
    print_success "Containers built successfully"
}

# Function to start containers
start_containers() {
    print_header "Starting Containers"
    docker compose up -d
    print_success "Containers started successfully"
}

# Function to start containers with SSL
start_containers_ssl() {
    print_header "Starting Containers with SSL"
    if [ ! -f "docker-compose.ssl.yml" ]; then
        print_error "docker-compose.ssl.yml not found"
        return 1
    fi
    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d
    print_success "Containers started with SSL successfully"
}

# Function to build and publish images to Docker Hub
build_and_publish() {
    print_header "Build and Publish to Docker Hub"

    read -p "Docker Hub username/organization [openmrs]: " docker_org
    docker_org=${docker_org:-openmrs}

    read -p "Image tag [latest]: " image_tag
    image_tag=${image_tag:-latest}

    echo ""
    echo "Services to build and push:"
    echo "  1) frontend   -> ${docker_org}/openmrs-reference-application-3-frontend:${image_tag}"
    echo "  2) gateway    -> ${docker_org}/openmrs-reference-application-3-gateway:${image_tag}"
    echo "  3) backend    -> ${docker_org}/openmrs-reference-application-3-backend:${image_tag}"
    echo "  4) certbot    -> ${docker_org}/openmrs-reference-application-3-certbot:${image_tag}"
    echo "  5) All of the above"
    echo ""
    read -p "Select service to build and push (1-5): " publish_choice

    # Check Docker Hub login
    if ! docker info 2>/dev/null | grep -q "Username"; then
        echo "You do not appear to be logged in to Docker Hub."
        read -p "Do you want to log in now? (y/n): " login_choice
        if [[ $login_choice == "y" || $login_choice == "Y" ]]; then
            docker login
        else
            print_warning "Skipping login. Push may fail if not already authenticated."
        fi
    fi

    # Check if buildx is available
    if docker buildx version >/dev/null 2>&1; then
        use_buildx=true
        print_success "Docker Buildx detected. Using multi-platform build."
    else
        use_buildx=false
        print_warning "Docker Buildx not detected. Using standard docker build + push."
    fi

    build_push_service() {
        local service_name=$1
        local context_dir=$2
        local image_name=$3

        print_header "Building and pushing ${service_name}"

        if [ "$use_buildx" = true ]; then
            if docker buildx build --platform linux/amd64,linux/arm64 --push -t "${image_name}" "${context_dir}"; then
                print_success "${service_name} built and pushed successfully"
            else
                print_error "${service_name} build/push failed"
            fi
        else
            if docker build -t "${image_name}" "${context_dir}"; then
                if docker push "${image_name}"; then
                    print_success "${service_name} built and pushed successfully"
                else
                    print_error "${service_name} push failed"
                fi
            else
                print_error "${service_name} build failed"
            fi
        fi
    }

    case $publish_choice in
        1)
            build_push_service "frontend" "./frontend" "${docker_org}/openmrs-reference-application-3-frontend:${image_tag}"
            ;;
        2)
            build_push_service "gateway" "./gateway" "${docker_org}/openmrs-reference-application-3-gateway:${image_tag}"
            ;;
        3)
            build_push_service "backend" "." "${docker_org}/openmrs-reference-application-3-backend:${image_tag}"
            ;;
        4)
            build_push_service "certbot" "./certbot" "${docker_org}/openmrs-reference-application-3-certbot:${image_tag}"
            ;;
        5)
            build_push_service "frontend" "./frontend" "${docker_org}/openmrs-reference-application-3-frontend:${image_tag}"
            build_push_service "gateway" "./gateway" "${docker_org}/openmrs-reference-application-3-gateway:${image_tag}"
            build_push_service "backend" "." "${docker_org}/openmrs-reference-application-3-backend:${image_tag}"
            build_push_service "certbot" "./certbot" "${docker_org}/openmrs-reference-application-3-certbot:${image_tag}"
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

# Function to deploy published images to production
deploy_production() {
    print_header "Deploy to Production"

    read -p "Image tag to deploy [prod]: " deploy_tag
    deploy_tag=${deploy_tag:-prod}

    echo ""
    echo "SSL configuration:"
    echo "1) Deploy without SSL (HTTP only)"
    echo "2) Deploy with SSL (HTTPS)"
    read -p "Select option (1-2): " ssl_choice

    export TAG="${deploy_tag}"

    case $ssl_choice in
        1)
            print_header "Pulling images and deploying (HTTP)"
            docker compose pull
            docker compose up -d
            print_success "Production deployment (HTTP) complete"
            ;;
        2)
            if [ ! -f "docker-compose.ssl.yml" ]; then
                print_error "docker-compose.ssl.yml not found"
                return 1
            fi
            print_header "Pulling images and deploying (SSL/HTTPS)"
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml pull
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d
            print_success "Production deployment (SSL/HTTPS) complete"
            ;;
        *)
            print_error "Invalid SSL option"
            return 1
            ;;
    esac

    echo ""
    echo "Deployed images:"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
}

# Function to stop containers
stop_containers() {
    print_header "Stopping Containers"
    docker compose stop
    print_success "Containers stopped successfully"
}

# Function to delete containers
delete_containers() {
    print_header "Deleting Containers"
    read -p "Are you sure you want to delete all containers? (y/n): " confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        docker compose down
        print_success "Containers deleted successfully"
    else
        print_warning "Operation cancelled"
    fi
}

# Function to prune containers
prune_containers() {
    print_header "Pruning Docker System"
    read -p "This will remove all unused containers, networks, images, and volumes. Continue? (y/n): " confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        docker system prune -a --volumes
        print_success "Docker system pruned successfully"
    else
        print_warning "Operation cancelled"
    fi
}

# Function to show logs
show_logs() {
    print_header "Showing Container Logs"
    echo "Select service to view logs:"
    echo "1) All services"
    echo "2) Gateway"
    echo "3) Frontend"
    echo "4) Backend"
    echo "5) Database"
    read -p "Enter choice (1-5): " log_choice
    
    case $log_choice in
        1)
            docker-compose logs -f
            ;;
        2)
            docker-compose logs -f gateway
            ;;
        3)
            docker-compose logs -f frontend
            ;;
        4)
            docker-compose logs -f backend
            ;;
        5)
            docker-compose logs -f db
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

# Function to restart containers
restart_containers() {
    print_header "Restarting Containers"
    echo "Select service to restart:"
    echo "1) All services"
    echo "2) Gateway"
    echo "3) Frontend"
    echo "4) Backend"
    echo "5) Database"
    read -p "Enter choice (1-5): " restart_choice
    
    case $restart_choice in
        1)
            docker compose restart
            print_success "All containers restarted successfully"
            ;;
        2)
            docker compose restart gateway
            print_success "Gateway container restarted successfully"
            ;;
        3)
            docker compose restart frontend
            print_success "Frontend container restarted successfully"
            ;;
        4)
            docker compose restart backend
            print_success "Backend container restarted successfully"
            ;;
        5)
            docker compose restart db
            print_success "Database container restarted successfully"
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

# Function to copy static assets without rebuilding
copy_static_assets() {
    print_header "Copying Static Assets"
    echo "Select service to copy assets to:"
    echo "1) Frontend"
    echo "2) Gateway"
    read -p "Enter choice (1-2): " asset_choice

    case $asset_choice in
        1)
            echo ""
            echo "Frontend common destinations:"
            echo "  /usr/share/nginx/html/          (SPA root)"
            echo "  /usr/share/nginx/html/openmrs/spa/  (custom assets like logos)"
            default_dest="/usr/share/nginx/html/"
            ;;
        2)
            echo ""
            echo "Gateway common destinations:"
            echo "  /etc/nginx/       (nginx config)"
            echo "  /usr/share/nginx/html/  (static files)"
            default_dest="/etc/nginx/"
            ;;
        *)
            print_error "Invalid choice"
            return
            ;;
    esac

    echo ""
    read -p "Enter source path (local file or directory): " source_path
    if [ -z "$source_path" ]; then
        print_error "Source path cannot be empty"
        return
    fi
    if [ ! -e "$source_path" ]; then
        print_error "Source path does not exist: $source_path"
        return
    fi

    read -p "Enter destination path in container [${default_dest}]: " dest_path
    dest_path="${dest_path:-$default_dest}"

    container_name=$(docker compose ps -q $([ "$asset_choice" = "1" ] && echo "frontend" || echo "gateway") | xargs docker inspect -f '{{.Name}}' 2>/dev/null | sed 's/\///')
    if [ -z "$container_name" ]; then
        print_error "Container not running"
        return
    fi

    echo "Copying: $source_path -> $container_name:$dest_path"
    if docker cp "$source_path" "$container_name:$dest_path"; then
        print_success "Assets copied successfully to $container_name:$dest_path"
    else
        print_error "Failed to copy assets"
    fi
}

# Function to rebuild with no cache
rebuild_no_cache() {
    print_header "Rebuilding Containers (No Cache)"
    echo "Select service to rebuild:"
    echo "1) All services"
    echo "2) Gateway"
    echo "3) Frontend"
    echo "4) Backend"
    echo "5) Database"
    read -p "Enter choice (1-5): " rebuild_choice
    
    case $rebuild_choice in
        1)
            docker compose build --no-cache
            print_success "All containers rebuilt without cache"
            ;;
        2)
            docker compose build --no-cache gateway
            print_success "Gateway container rebuilt without cache"
            ;;
        3)
            docker compose build --no-cache frontend
            print_success "Frontend container rebuilt without cache"
            ;;
        4)
            docker compose build --no-cache backend
            print_success "Backend container rebuilt without cache"
            ;;
        5)
            docker compose build --no-cache db
            print_success "Database container rebuilt without cache"
            ;;
        *)
            print_error "Invalid choice"
            return
            ;;
    esac
    
    read -p "Do you want to restart the containers? (y/n): " restart
    if [[ $restart == "y" || $restart == "Y" ]]; then
        if [[ $rebuild_choice == "1" ]]; then
            docker compose up -d
            print_success "All containers restarted successfully"
        else
            case $rebuild_choice in
                2)
                    docker compose up -d gateway
                    print_success "Gateway container restarted successfully"
                    ;;
                3)
                    docker compose up -d frontend
                    print_success "Frontend container restarted successfully"
                    ;;
                4)
                    docker compose up -d backend
                    print_success "Backend container restarted successfully"
                    ;;
                5)
                    docker compose up -d db
                    print_success "Database container restarted successfully"
                    ;;
            esac
        fi
    fi
}

# Function to rebuild with SSL and no cache
rebuild_ssl_no_cache() {
    print_header "Rebuilding Containers with SSL (No Cache)"
    if [ ! -f "docker-compose.ssl.yml" ]; then
        print_error "docker-compose.ssl.yml not found"
        return 1
    fi
    echo "Select service to rebuild:"
    echo "1) All services"
    echo "2) Gateway"
    echo "3) Frontend"
    echo "4) Backend"
    echo "5) Database"
    echo "6) Certbot"
    read -p "Enter choice (1-6): " rebuild_choice

    case $rebuild_choice in
        1)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache
            print_success "All containers rebuilt with SSL without cache"
            ;;
        2)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache gateway
            print_success "Gateway container rebuilt with SSL without cache"
            ;;
        3)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache frontend
            print_success "Frontend container rebuilt with SSL without cache"
            ;;
        4)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache backend
            print_success "Backend container rebuilt with SSL without cache"
            ;;
        5)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache db
            print_success "Database container rebuilt with SSL without cache"
            ;;
        6)
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml build --no-cache certbot
            print_success "Certbot container rebuilt without cache"
            ;;
        *)
            print_error "Invalid choice"
            return
            ;;
    esac

    read -p "Do you want to restart the containers? (y/n): " restart
    if [[ $restart == "y" || $restart == "Y" ]]; then
        if [[ $rebuild_choice == "1" ]]; then
            docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d
            print_success "All containers restarted with SSL successfully"
        else
            case $rebuild_choice in
                2)
                    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d gateway
                    print_success "Gateway container restarted with SSL successfully"
                    ;;
                3)
                    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d frontend
                    print_success "Frontend container restarted with SSL successfully"
                    ;;
                4)
                    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d backend
                    print_success "Backend container restarted with SSL successfully"
                    ;;
                5)
                    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d db
                    print_success "Database container restarted with SSL successfully"
                    ;;
                6)
                    docker compose -f docker-compose.yml -f docker-compose.ssl.yml up -d certbot
                    print_success "Certbot container restarted successfully"
                    ;;
            esac
        fi
    fi
}

# Function to show container status
show_status() {
    print_header "Container Status"
    docker compose ps
}

# Function to view resource usage
show_resources() {
    print_header "Resource Usage"
    docker stats --no-stream
}

# Main menu function
show_menu() {
    clear
    print_header "Docker Management Menu"
    echo "1) Build containers"
    echo "2) Start containers"
    echo "3) Start containers with SSL"
    echo "4) Stop containers"
    echo "5) Delete containers"
    echo "6) Prune containers (remove unused resources)"
    echo "7) Show logs"
    echo "8) Restart containers"
    echo "9) Copy static assets (without rebuilding)"
    echo "10) Rebuild with no cache"
    echo "11) Rebuild with SSL and no cache"
    echo "12) Show container status"
    echo "13) Show resource usage"
    echo "14) Build and publish to Docker Hub"
    echo "15) Deploy to production"
    echo "16) Exit"
    echo ""
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice (1-16): " choice

    case $choice in
        1)
            build_containers
            ;;
        2)
            start_containers
            ;;
        3)
            start_containers_ssl
            ;;
        4)
            stop_containers
            ;;
        5)
            delete_containers
            ;;
        6)
            prune_containers
            ;;
        7)
            show_logs
            ;;
        8)
            restart_containers
            ;;
        9)
            copy_static_assets
            ;;
        10)
            rebuild_no_cache
            ;;
        11)
            rebuild_ssl_no_cache
            ;;
        12)
            show_status
            ;;
        13)
            show_resources
            ;;
        14)
            build_and_publish
            ;;
        15)
            deploy_production
            ;;
        16)
            print_success "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please enter a number between 1 and 16."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done