#!/bin/bash
# Auto-scaling health check script for Moodle app servers
set -e

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
MOODLE_URL="http://localhost/"

check_health() {
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$MOODLE_URL")
    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
        return 0
    else
        return 1
    fi
}

if check_health; then
    echo "OK $(date -u +%Y-%m-%dT%H:%M:%SZ) instance=$INSTANCE_ID status=healthy"
    exit 0
else
    echo "CRITICAL $(date -u +%Y-%m-%dT%H:%M:%SZ) instance=$INSTANCE_ID status=unhealthy"
    exit 1
fi
