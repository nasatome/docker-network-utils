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

# Get current IPs for comparison
CURRENT_V4=$(grep "^CLOUDFLARE_IPS_V4=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")

if [ "$CURRENT_V4" = "$V4" ]; then
    log "No changes detected in Cloudflare IP ranges"
    exit 0
fi

log "Changes detected in Cloudflare IP ranges"

# Update .env file
log "Updating .env file..."

# Create temp file
TEMP_ENV=$(mktemp)
cp "$ENV_FILE" "$TEMP_ENV"

# Update or add CLOUDFLARE_IPS_V4
if grep -q "^CLOUDFLARE_IPS_V4=" "$TEMP_ENV"; then
    sed -i "s|^CLOUDFLARE_IPS_V4=.*|CLOUDFLARE_IPS_V4=$V4|" "$TEMP_ENV"
else
    echo "CLOUDFLARE_IPS_V4=$V4" >> "$TEMP_ENV"
fi

# Update or add CLOUDFLARE_IPS_V6
if grep -q "^CLOUDFLARE_IPS_V6=" "$TEMP_ENV"; then
    sed -i "s|^CLOUDFLARE_IPS_V6=.*|CLOUDFLARE_IPS_V6=$V6|" "$TEMP_ENV"
else
    echo "CLOUDFLARE_IPS_V6=$V6" >> "$TEMP_ENV"
fi

# Update combined variable (remove old reference-style if exists)
COMBINED="${V4},${V6}"
sed -i '/^CLOUDFLARE_IPS=\${/d' "$TEMP_ENV"  # Remove ${VAR} style reference
if grep -q "^CLOUDFLARE_IPS=" "$TEMP_ENV"; then
    sed -i "s|^CLOUDFLARE_IPS=.*|CLOUDFLARE_IPS=$COMBINED|" "$TEMP_ENV"
else
    echo "CLOUDFLARE_IPS=$COMBINED" >> "$TEMP_ENV"
fi

# Move temp file to .env
mv "$TEMP_ENV" "$ENV_FILE"
log "Updated .env with new Cloudflare IPs"

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
