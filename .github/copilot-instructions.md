# RustDeskPro-WSS

RustDeskPro-WSS is a production-ready Docker Compose setup for running RustDesk Server Pro (hbbr/hbbs) behind Caddy reverse proxy with automatic HTTPS, secure file permissions, and hardened firewall configuration.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Environment Setup
- Ensure Docker Engine and Docker Compose Plugin are installed:
  ```bash
  docker --version
  docker compose version
  ```
- The setup requires Linux with host networking support (network_mode: host)
- Root privileges are required for installation (creates system users and directories)

### Essential Commands and Timing
- **NEVER CANCEL**: All Docker operations complete quickly (under 10 seconds typically)
- Set timeout to 60+ seconds for Docker operations as a safety buffer

#### Bootstrap the Repository
```bash
# Clone and enter directory
git clone https://github.com/tommyvange/RustDeskPro-WSS.git
cd RustDeskPro-WSS

# Create environment configuration
cp .env.example .env
${EDITOR:-nano} .env
```

#### Validate Configuration
```bash
# Test Docker Compose syntax (instant)
docker compose config

# Test Caddyfile syntax (requires caddy image, ~1-2 seconds)
docker run --rm -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile" caddy:latest caddy validate --config /etc/caddy/Caddyfile
```

#### Install and Deploy
```bash
# Make installer executable
chmod +x install.sh

# Run automated installation (requires root, ~10-15 seconds total)
# NEVER CANCEL: Process completes quickly but requires root for user/directory creation
sudo ./install.sh
```

#### Pull Images Manually (if needed)
```bash
# Pull all required Docker images (~7-10 seconds)
# NEVER CANCEL: Set timeout to 60+ seconds
docker compose pull
```

#### Container Management
```bash
# Start services (~1 second)
docker compose up -d --force-recreate

# Check container status (instant)
docker compose ps

# View logs (instant)
docker compose logs
docker compose logs -f  # follow logs

# Stop services (~2 seconds)
docker compose down
```

## Validation

### Essential Validation Steps
Always perform these validation steps after making changes:

1. **Configuration Validation**:
   ```bash
   # Validate Docker Compose configuration
   docker compose config
   
   # Validate environment variables are set
   grep -v '^#' .env | grep -v '^$'
   ```

2. **Container Health Check**:
   ```bash
   # Start containers and verify they're running
   docker compose up -d
   docker compose ps
   
   # Check for any container errors
   docker compose logs --no-color | grep -i error || echo "No errors found"
   ```

3. **Port and Network Validation**:
   ```bash
   # Verify required ports are available (21114, 21115, 21116, 21117, 21118, 21119)
   ss -tuln | grep -E ':(21114|21115|21116|21117|21118|21119|80|443)'
   
   # Test Caddy configuration syntax
   docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
   ```

4. **File Permissions Validation**:
   ```bash
   # Verify directory permissions are correct
   ls -la /srv/caddy/ /srv/rustdesk/ 2>/dev/null || echo "Directories not created yet"
   ```

### Manual Validation Scenarios
After deployment, test these scenarios:

1. **HTTP/HTTPS Connectivity**: Visit `https://yourdomain.com` (should show RustDesk console interface)
2. **WebSocket Endpoints**: Test `/ws/id` and `/ws/relay` endpoints are accessible
3. **Container Logs**: Verify no critical errors in `docker compose logs`

### You Cannot Test Interactively
- The RustDesk Pro server requires a valid license key for full functionality
- WebSocket connections require RustDesk client applications
- Some features only work with actual RustDesk clients connecting

## Repository Structure and Key Files

### Essential Files
```
.
├── README.md              # Complete setup documentation
├── install.sh             # Automated installation script (main entry point)
├── compose.yml            # Docker services definition
├── Caddyfile              # Reverse proxy configuration template
├── .env.example           # Environment configuration template
└── LICENSE                # GPLv3 license
```

### Key Configuration Points
- **compose.yml**: Defines 3 services (hbbr, hbbs, caddy) with host networking
- **Caddyfile**: Template with EXAMPLE.COM placeholder and optional CORS block
- **.env**: Contains domains, file paths, CORS settings, and user IDs

## Common Workflows

### Environment Configuration (.env file)
Required variables that must be set:
```bash
DOMAINS=your.domain.com              # Comma-separated domain list
FILE_LOCATION_CADDY=/srv/caddy       # Caddy data/config path
FILE_LOCATION_RUSTDESK=/srv/rustdesk # RustDesk data path
RUSTDESK_CORS=true                   # Enable/disable CORS restrictions
# UIDs/GIDs automatically populated by install.sh
```

### Caddyfile Processing
The install script automatically:
1. Replaces `EXAMPLE.COM` with your domains (comma → space conversion)
2. Removes CORS block if `RUSTDESK_CORS=false`
3. Sets proper file ownership (caddy:caddy, mode 640)

### Manual Setup Alternative
If not using install.sh:
```bash
# Create system users
sudo useradd --system --no-create-home --shell /bin/false rustdesk
sudo useradd --system --no-create-home --shell /bin/false caddy

# Create directories
sudo mkdir -p /srv/rustdesk/data /srv/caddy/{data,config}
sudo chown -R rustdesk:rustdesk /srv/rustdesk
sudo chown -R caddy:caddy /srv/caddy

# Process Caddyfile manually
sed 's/EXAMPLE\.COM/your.domain.com/g' Caddyfile > /srv/caddy/Caddyfile
sudo chown caddy:caddy /srv/caddy/Caddyfile
sudo chmod 640 /srv/caddy/Caddyfile

# Update .env with user IDs
echo "RUSTDESK_UID=$(id -u rustdesk)" >> .env
echo "RUSTDESK_GID=$(id -g rustdesk)" >> .env
echo "CADDY_UID=$(id -u caddy)" >> .env
echo "CADDY_GID=$(id -g caddy)" >> .env
```

## Troubleshooting

### Common Issues and Solutions

1. **Permission Errors**: 
   - Ensure running `install.sh` with sudo
   - Verify user/group ownership matches .env UID/GID values

2. **Docker Compose Failures**:
   - Check Docker daemon is running: `systemctl status docker`
   - Validate .env has all required variables: `docker compose config`

3. **Container Startup Issues**:
   - Host networking requires Linux (not macOS/Windows Docker Desktop)
   - Check port conflicts: `ss -tuln | grep -E ':(21114|21115|21116|21117|21118|21119)'`

4. **Caddy Certificate Issues**:
   - Ensure ports 80/443 are open in firewall
   - Verify DNS points to server IP: `dig yourdomain.com`

### Useful Diagnostic Commands
```bash
# Full system status check
docker compose ps && docker compose logs --tail=20

# Network connectivity test
curl -I http://localhost:21114 || echo "RustDesk not responding"

# File permission audit
find /srv -type d -exec ls -ld {} \; 2>/dev/null

# Container resource usage
docker stats --no-stream
```

## Development and Modification Guidelines

### Making Changes to Configuration
1. Always backup .env before modifications
2. Use `docker compose config` to validate after changes
3. Test with `docker compose up -d --force-recreate` after changes
4. Monitor logs with `docker compose logs -f` during testing

### Modifying the Caddyfile
1. Edit the template `Caddyfile` in repository root
2. Re-run `sudo ./install.sh` to process and deploy changes
3. Or manually process and copy to `/srv/caddy/Caddyfile`
4. Restart Caddy: `docker compose restart caddy`

### Infrastructure Changes
- Host networking is mandatory for RustDesk Pro license validation
- User ID mapping is critical for security - maintain rustdesk/caddy system users
- File permissions (750 for directories, 640 for Caddyfile) are security requirements

This setup prioritizes security and production readiness over development convenience. Always test changes in a staging environment first.