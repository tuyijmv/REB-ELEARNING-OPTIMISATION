#!/bin/bash
# Health check script for Moodle deployment
set -e

MOODLE_URL="${MOODLE_URL:-http://localhost:8080}"
TIMEOUT="${TIMEOUT:-10}"
EXPECTED_STATUS="${EXPECTED_STATUS:-200}"

echo "Checking Moodle health at $MOODLE_URL"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$MOODLE_URL")

if [ "$HTTP_CODE" -eq "$EXPECTED_STATUS" ]; then
    echo "Health check PASSED (HTTP $HTTP_CODE)"
    exit 0
else
    echo "Health check FAILED (HTTP $HTTP_CODE, expected $EXPECTED_STATUS)"
    exit 1
fi
