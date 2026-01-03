#!/bin/sh
# update-cloudflare-ips.sh
#
# Downloads Cloudflare IP ranges and updates .env file
# Designed to run via Ofelia cron scheduler
#
# Exit codes:
#   0 - Success (no changes or updated successfully)
#   1 - Failed to download IPs
#   2 - Failed to update config
#   3 - Failed to restart Traefik

set -e

# Configuration
ENV_FILE="${ENV_FILE:-/etc/traefik-env/.env}"
CLOUDFLARE_IPV4_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6_URL="https://www.cloudflare.com/ips-v6"
NOTIFY_SCRIPT="/scripts/notify-discord.sh"

# Logging with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

notify_error() {
    if [ -x "$NOTIFY_SCRIPT" ]; then
        $NOTIFY_SCRIPT "$1"
    fi
}

# Download Cloudflare IP ranges
log "Downloading Cloudflare IP ranges..."

V4=$(curl -sf --max-time 30 "$CLOUDFLARE_IPV4_URL" | tr '\n' ',' | sed 's/,$//')
V6=$(curl -sf --max-time 30 "$CLOUDFLARE_IPV6_URL" | tr '\n' ',' | sed 's/,$//')

if [ -z "$V4" ]; then
    error "Failed to download IPv4 ranges"
    notify_error "Cloudflare IP update failed - IPv4 download error"
    exit 1
fi

if [ -z "$V6" ]; then
    error "Failed to download IPv6 ranges"
    notify_error "Cloudflare IP update failed - IPv6 download error"
    exit 1
fi

# Count entries
IPV4_COUNT=$(echo "$V4" | tr ',' '\n' | wc -l)
IPV6_COUNT=$(echo "$V6" | tr ',' '\n' | wc -l)

log "Downloaded $IPV4_COUNT IPv4 and $IPV6_COUNT IPv6 ranges"

# Validate downloads
if [ "$IPV4_COUNT" -lt 10 ]; then
    error "IPv4 has too few entries ($IPV4_COUNT). Aborting."
    notify_error "Cloudflare IP update failed - too few IPv4 entries"
    exit 1
fi

if [ "$IPV6_COUNT" -lt 5 ]; then
    error "IPv6 has too few entries ($IPV6_COUNT). Aborting."
    notify_error "Cloudflare IP update failed - too few IPv6 entries"
    exit 1
fi

# Check .env file exists
if [ ! -f "$ENV_FILE" ]; then
    error ".env file not found at $ENV_FILE"
    notify_error "Cloudflare IP update failed - .env not found"
    exit 2
fi

# Get current IPs for comparison (only read CLOUDFLARE_IPS line)
CURRENT_IPS=$(grep "^CLOUDFLARE_IPS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
COMBINED="${V4},${V6}"

if [ "$CURRENT_IPS" = "$COMBINED" ]; then
    log "No changes detected in Cloudflare IP ranges"
    exit 0
fi

log "Changes detected in Cloudflare IP ranges"

# Update ONLY the CLOUDFLARE_IPS line in .env (no secrets read)
log "Updating CLOUDFLARE_IPS in .env..."

if grep -q "^CLOUDFLARE_IPS=" "$ENV_FILE"; then
    # Update existing line
    sed -i "s|^CLOUDFLARE_IPS=.*|CLOUDFLARE_IPS=$COMBINED|" "$ENV_FILE"
else
    # Add new line
    echo "CLOUDFLARE_IPS=$COMBINED" >> "$ENV_FILE"
fi

log "Updated CLOUDFLARE_IPS in .env"

# Restart Traefik
log "Restarting Traefik..."
TRAEFIK=$(docker ps -q -f label=com.docker.compose.service=traefik)

if [ -z "$TRAEFIK" ]; then
    error "Traefik container not found"
    notify_error "Cloudflare IP update - Traefik container not found"
    exit 3
fi

docker restart "$TRAEFIK"
sleep 30

# Verify Traefik is running
if docker ps -q -f id="$TRAEFIK" -f status=running | grep -q .; then
    log "Traefik restarted successfully"
else
    error "Traefik failed to restart"
    notify_error "Traefik Down - failed to restart after Cloudflare IP update"
    exit 3
fi

log "Cloudflare IP update completed successfully"
exit 0
