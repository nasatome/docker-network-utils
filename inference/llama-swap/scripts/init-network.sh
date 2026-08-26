#!/usr/bin/env bash
# Crea la red docker externa ai_inference si no existe. Idempotente.
set -euo pipefail

NETWORK_NAME="${LLM_NETWORK_NAME:-ai_inference}"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' already exists."
else
  docker network create --driver bridge "$NETWORK_NAME"
  echo "Network '$NETWORK_NAME' created."
fi
