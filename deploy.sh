#!/usr/bin/env bash
set -e

echo "======================================"
echo " Deploying Hono Metrics Service"
echo "======================================"

docker compose down

docker compose build

docker compose up -d

echo ""
echo "Service status:"
docker compose ps

echo ""
echo "Test endpoint:"
curl -s http://127.0.0.1:3000/health || true
