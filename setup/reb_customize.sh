#!/bin/bash
# Re-applies the REB E-Learning branding customizations.
#
# Assumes the Docker Compose stack is already running and Moodle has been
# installed (config.php exists). It installs any pending plugins (so e.g.
# the Moove theme is registered in the database) and then runs the
# idempotent customization script.
#
# Usage:
#   ./setup/reb_customize.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Resolve project root (parent of this script's directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

if ! command -v docker >/dev/null 2>&1; then
    log_error "docker is not installed or not on PATH."
    exit 1
fi

# Ensure the stack is up.
if ! docker compose ps 2>/dev/null | grep -q "moodle_php"; then
    log_error "The 'moodle_php' container is not running. Start the stack first: docker compose up -d"
    exit 1
fi

# Locate the Moodle CLI directory inside the container.
CLI_DIR=$(docker compose exec -T moodle_php bash -c \
    'for d in /var/www/html/moodle_app/public/admin/cli /var/www/html/moodle_app/admin/cli; do [ -f "$d/upgrade.php" ] && echo "$d" && break; done' \
    | tr -d '\r')

if [ -z "$CLI_DIR" ]; then
    log_error "Could not locate Moodle admin/cli inside the container."
    exit 1
fi

# Install any pending plugins (e.g. the Moove theme) before customizing.
log_info "Running Moodle upgrade to install pending plugins..."
docker compose exec -T moodle_php php "$CLI_DIR/upgrade.php" --non-interactive || \
    log_info "Upgrade reported issues (continuing)."

# Run the customization script as www-data so generated files in moodledata
# are owned correctly.
log_info "Applying REB customizations..."
docker compose exec -T -u www-data moodle_php php /var/www/html/moodle_app/customize_moodle.php

log_ok "REB customizations applied."
