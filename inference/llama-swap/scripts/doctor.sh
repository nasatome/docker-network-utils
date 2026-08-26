#!/usr/bin/env bash
# Health probe de llama-swap + lista de modelos disponibles + GPU snapshot.
set -euo pipefail

PORT="${HOST_PORT:-8222}"
URL="http://127.0.0.1:${PORT}"

echo "=== llama-swap health ($URL) ==="
if curl -sf "$URL/" >/dev/null 2>&1; then
  echo "OK"
else
  echo "DOWN"
  exit 1
fi

echo ""
echo "=== Available models ==="
curl -sS "$URL/v1/models" | python3 -m json.tool 2>/dev/null || curl -sS "$URL/v1/models"

echo ""
echo "=== GPU snapshot ==="
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv
