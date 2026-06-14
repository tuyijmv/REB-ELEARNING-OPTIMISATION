#!/bin/bash
# Database failover switch script for Moodle HA setup
set -e

PRIMARY_ENDPOINT="$1"
REPLICA_ENDPOINT="$2"
NEW_PRIMARY="$3"

echo "=== Moodle Database Failover ==="
echo "Primary: $PRIMARY_ENDPOINT"
echo "Replica: $REPLICA_ENDPOINT"
echo "Promoting replica to primary: $NEW_PRIMARY"

# Update .env with new database endpoint
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    sed -i "s|^DB_HOST=.*|DB_HOST=$NEW_PRIMARY|" "$ENV_FILE"
    echo ".env updated with new DB_HOST=$NEW_PRIMARY"
fi

# Update Terraform state if needed
echo "Please update your Terraform state manually if using managed databases."

echo "Restarting app containers..."
docker compose up -d --force-recreate php nginx

echo "Failover complete. Verify site is accessible."
echo "Run: docker compose logs -f"
