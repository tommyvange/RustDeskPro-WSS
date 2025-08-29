#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        print_error "Usage: sudo ./install.sh"
        exit 1
    fi
    print_success "Running as root"
}

# Function to configure UDP buffer sizes for optimal QUIC performance
configure_udp_buffers() {
    print_status "Configuring UDP buffer sizes for optimal HTTP/3 (QUIC) performance..."
    
    # Check current values
    current_rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "0")
    current_wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "0")
    
    # Recommended values for QUIC (in bytes)
    # 7168 KiB = 7340032 bytes (as requested by QUIC in the error)
    # Set to 8MB (8388608) to have some headroom
    target_rmem_max=8388608
    target_wmem_max=8388608
    target_rmem_default=1048576
    target_wmem_default=1048576
    
    print_status "Current UDP receive buffer max: $(($current_rmem_max / 1024)) KiB"
    print_status "Current UDP send buffer max: $(($current_wmem_max / 1024)) KiB"
    print_status "Setting UDP buffers to: $(($target_rmem_max / 1024)) KiB"
    
    # Configure sysctl values
    sysctl -w net.core.rmem_max=$target_rmem_max
    sysctl -w net.core.rmem_default=$target_rmem_default
    sysctl -w net.core.wmem_max=$target_wmem_max
    sysctl -w net.core.wmem_default=$target_wmem_default
    
    # Make changes persistent across reboots
    print_status "Making UDP buffer settings persistent..."
    
    # Create or update sysctl configuration file
    cat > /etc/sysctl.d/99-rustdesk-quic.conf << EOF
# UDP buffer sizes for optimal QUIC performance (HTTP/3)
# Required for Caddy/RustDesk to avoid UDP buffer warnings
net.core.rmem_max = $target_rmem_max
net.core.rmem_default = $target_rmem_default
net.core.wmem_max = $target_wmem_max
net.core.wmem_default = $target_wmem_default
EOF
    
    print_success "UDP buffer sizes configured successfully"
    print_status "New UDP receive buffer max: $(($target_rmem_max / 1024)) KiB"
    print_status "Changes are persistent and will survive reboots"
}

# Function to check if Docker is installed
check_docker() {
    print_status "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        print_error "Please install Docker first:"
        print_error "https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed!"
        print_error "Please install Docker Compose first:"
        print_error "https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    print_success "Docker and Docker Compose are installed"
}

# Function to load environment variables
load_env() {
    if [[ ! -f ".env" ]]; then
        print_error ".env file not found!"
        print_error "Please create a .env file with the required variables"
        exit 1
    fi
    
    print_status "Loading environment variables from .env file..."
    source .env
    
    # Validate required variables
    if [[ -z "$DOMAINS" ]]; then
        print_error "DOMAINS variable not set in .env file"
        exit 1
    fi
    
    if [[ -z "$FILE_LOCATION_CADDY" ]]; then
        print_error "FILE_LOCATION_CADDY variable not set in .env file"
        exit 1
    fi
    
    if [[ -z "$FILE_LOCATION_RUSTDESK" ]]; then
        print_error "FILE_LOCATION_RUSTDESK variable not set in .env file"
        exit 1
    fi
    
    if [[ -z "$RUSTDESK_CORS" ]]; then
        print_warning "RUSTDESK_CORS variable not set in .env file, defaulting to 'true'"
        RUSTDESK_CORS="true"
    fi
    
    if [[ -z "$RUSTDESK_NOINDEX" ]]; then
        print_warning "RUSTDESK_NOINDEX variable not set in .env file, defaulting to 'true'"
        RUSTDESK_NOINDEX="true"
    fi
    
    if [[ -z "$HIDE_SERVER_DETAILS" ]]; then
        print_warning "HIDE_SERVER_DETAILS variable not set in .env file, defaulting to 'true'"
        HIDE_SERVER_DETAILS="true"
    fi
    
    # Note: UID/GID variables will be set by create_users function
    
    print_success "Environment variables loaded successfully"
    print_status "Domains: $DOMAINS"
    print_status "Caddy location: $FILE_LOCATION_CADDY"
    print_status "RustDesk location: $FILE_LOCATION_RUSTDESK"
    print_status "CORS enabled: $RUSTDESK_CORS"
    print_status "Robots noindex enabled: $RUSTDESK_NOINDEX"
    print_status "Hide server details enabled: $HIDE_SERVER_DETAILS"
}

# Function to create system users
create_users() {
    print_status "Creating system users..."
    
    # Create rustdesk user
    if ! id -u rustdesk &>/dev/null; then
        print_status "Creating rustdesk user..."
        useradd --system --no-create-home --shell /bin/false rustdesk
        print_success "Created rustdesk user"
    else
        print_status "rustdesk user already exists"
    fi
    
    # Create caddy user
    if ! id -u caddy &>/dev/null; then
        print_status "Creating caddy user..."
        useradd --system --no-create-home --shell /bin/false caddy
        print_success "Created caddy user"
    else
        print_status "caddy user already exists"
    fi
    
    # Get user IDs and update .env file
    print_status "Getting user IDs and updating .env file..."
    RUSTDESK_UID=$(id -u rustdesk)
    RUSTDESK_GID=$(id -g rustdesk)
    CADDY_UID=$(id -u caddy)
    CADDY_GID=$(id -g caddy)
    
    # Update .env file with user IDs
    sed -i "s/^RUSTDESK_UID=.*/RUSTDESK_UID=$RUSTDESK_UID/" .env
    sed -i "s/^RUSTDESK_GID=.*/RUSTDESK_GID=$RUSTDESK_GID/" .env
    sed -i "s/^CADDY_UID=.*/CADDY_UID=$CADDY_UID/" .env
    sed -i "s/^CADDY_GID=.*/CADDY_GID=$CADDY_GID/" .env
    
    print_success "User IDs updated in .env file"
    print_status "RustDesk UID:GID = $RUSTDESK_UID:$RUSTDESK_GID"
    print_status "Caddy UID:GID = $CADDY_UID:$CADDY_GID"
}

# Function to create directories and set permissions
create_directories() {
    print_status "Creating directories and setting permissions..."
    
    # Create RustDesk directories
    print_status "Creating RustDesk directories at $FILE_LOCATION_RUSTDESK..."
    mkdir -p "$FILE_LOCATION_RUSTDESK/data"
    chown -R rustdesk:rustdesk "$FILE_LOCATION_RUSTDESK"
    chmod -R 750 "$FILE_LOCATION_RUSTDESK"
    print_success "RustDesk directories created and secured"
    
    # Create Caddy directories
    print_status "Creating Caddy directories at $FILE_LOCATION_CADDY..."
    mkdir -p "$FILE_LOCATION_CADDY/data"
    mkdir -p "$FILE_LOCATION_CADDY/config"
    chown -R caddy:caddy "$FILE_LOCATION_CADDY"
    chmod -R 750 "$FILE_LOCATION_CADDY"
    print_success "Caddy directories created and secured"
}

# Function to process and copy Caddyfile
process_caddyfile() {
    print_status "Processing Caddyfile..."
    
    if [[ ! -f "Caddyfile" ]]; then
        print_error "Caddyfile not found in current directory!"
        exit 1
    fi
    
    # Create a temporary file for processing
    temp_caddyfile=$(mktemp)
    cp Caddyfile "$temp_caddyfile"
    
    # Replace EXAMPLE.COM with actual domains
    print_status "Replacing domains in Caddyfile..."
    # Convert comma-separated domains to space-separated for Caddyfile format
    formatted_domains=$(echo "$DOMAINS" | sed 's/,/ /g')
    sed -i "s/EXAMPLE\.COM/$formatted_domains/g" "$temp_caddyfile"
    
    # Handle CORS section
    if [[ "$RUSTDESK_CORS" == "false" ]]; then
        print_status "Removing CORS section (RUSTDESK_CORS=false)..."
        # Remove everything between and including CORS markers
        sed -i '/### CORS - START ###/,/### CORS - END ###/d' "$temp_caddyfile"
    else
        print_status "Keeping CORS section (RUSTDESK_CORS=true)"
    fi
    
    # Handle ROBOTS section
    if [[ "$RUSTDESK_NOINDEX" == "false" ]]; then
        print_status "Removing ROBOTS section (RUSTDESK_NOINDEX=false)..."
        # Remove everything between and including ROBOTS markers
        sed -i '/### ROBOTS - START ###/,/### ROBOTS - END ###/d' "$temp_caddyfile"
    else
        print_status "Keeping ROBOTS section (RUSTDESK_NOINDEX=true)"
    fi
    
    # Handle SERVER_DETAILS section
    if [[ "$HIDE_SERVER_DETAILS" == "false" ]]; then
        print_status "Removing SERVER_DETAILS section (HIDE_SERVER_DETAILS=false)..."
        # Remove everything between and including SERVER_DETAILS markers
        sed -i '/### SERVER_DETAILS - START ###/,/### SERVER_DETAILS - END ###/d' "$temp_caddyfile"
    else
        print_status "Keeping SERVER_DETAILS section (HIDE_SERVER_DETAILS=true)"
    fi
    
    # Copy processed Caddyfile to destination
    cp "$temp_caddyfile" "$FILE_LOCATION_CADDY/Caddyfile"
    chown caddy:caddy "$FILE_LOCATION_CADDY/Caddyfile"
    chmod 640 "$FILE_LOCATION_CADDY/Caddyfile"
    
    # Clean up
    rm "$temp_caddyfile"
    
    print_success "Caddyfile processed and copied successfully"
}

# Function to start Docker services
start_services() {
    print_status "Stopping any existing services..."
    docker compose down 2>/dev/null || true
    
    print_status "Pulling latest images..."
    if ! docker compose pull; then
        print_warning "Failed to pull some images, continuing with local versions..."
    fi
    
    print_status "Starting Docker services (forcing recreation)..."
    
    if ! docker compose up -d --force-recreate; then
        print_error "Failed to start Docker services!"
        print_error "Check the logs with: docker compose logs"
        exit 1
    fi
    
    print_success "Docker services started successfully!"
    
    # Show status
    print_status "Container status:"
    docker compose ps
}

# Main execution
main() {
    echo "=============================================="
    echo "    RustDeskPro-WSS Installation Script"
    echo "=============================================="
    echo
    
    check_root
    check_docker
    configure_udp_buffers
    load_env
    create_users
    
    # Reload environment variables after user IDs are updated
    print_status "Reloading environment variables..."
    source .env
    
    create_directories
    process_caddyfile
    start_services
    
    echo
    echo "=============================================="
    print_success "Installation completed successfully!"
    echo "=============================================="
    echo
    print_status "Your RustDesk server is now running with the following configuration:"
    print_status "- Domains: $DOMAINS"
    print_status "- CORS enabled: $RUSTDESK_CORS"
    print_status "- Robots noindex enabled: $RUSTDESK_NOINDEX"
    print_status "- Hide server details enabled: $HIDE_SERVER_DETAILS"
    print_status "- Data location: $FILE_LOCATION_RUSTDESK"
    print_status "- Caddy config location: $FILE_LOCATION_CADDY"
    echo
    print_status "You can check the status with: docker compose ps"
    print_status "View logs with: docker compose logs"
    print_status "Stop services with: docker compose down"
    echo
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
