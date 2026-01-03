#!/bin/sh
# Notify Discord if Traefik is down
# Usage: notify-discord.sh [message words...]

WEBHOOK_FILE="/etc/discord-webhook"
MESSAGE="${*:-Traefik is down}"

if [ ! -f "$WEBHOOK_FILE" ]; then
    echo "[WARN] No webhook file found at $WEBHOOK_FILE"
    exit 0
fi

WEBHOOK=$(cat "$WEBHOOK_FILE")

if [ -z "$WEBHOOK" ]; then
    echo "[WARN] Webhook file is empty"
    exit 0
fi

# Send notification
curl -sf -H "Content-Type: application/json" \
    -d "{\"content\":\"$MESSAGE\"}" \
    "$WEBHOOK"

echo "[OK] Discord notification sent"
