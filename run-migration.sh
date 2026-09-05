#!/bin/bash

#================================================================================
# Moodle Production-to-Dev Migration using pgloader
#
# This script sets up an SSH tunnel to the production server and uses pgloader
# to migrate data directly from MariaDB to PostgreSQL with proper type conversion.
#
# PREREQUISITES:
# 1. Configure .env.prod-migration with production credentials
# 2. Ensure Docker services are running: docker compose up -d
# 3. Have SSH access to the production server
#
# USAGE:
#   ./run-migration.sh
#
# PROCESS:
# 1. Creates SSH tunnel to production MariaDB (local port 13306 → remote 3306)
# 2. Runs pgloader to migrate database (auto-converts MySQL→PostgreSQL)
# 3. Cleans up SSH tunnel
#
# NOTE: This will DROP and recreate the entire database schema!
#================================================================================

set -e

# Load environment variables
if [ -f .env.prod-migration ]; then
    echo "📋 Loading configuration from .env.prod-migration"
    set -a
    source .env.prod-migration
    set +a
else
    echo "❌ Error: .env.prod-migration not found"
    echo "Copy .env.prod-migration.example to .env.prod-migration and configure it."
    exit 1
fi

# Required variables
PROD_SSH_USER="${PROD_SSH_USER:-root}"
PROD_SSH_HOST="${PROD_SSH_HOST}"
PROD_DB_USER="${PROD_DB_USER:-root}"
PROD_DB_PASS="${PROD_DB_PASS}"
PROD_DB_NAME="${PROD_DB_NAME}"
PROD_DB_PORT="${PROD_DB_PORT:-3306}"
LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-13306}"

# Validate required configuration
REQUIRED_VARS=("PROD_SSH_HOST" "PROD_DB_PASS" "PROD_DB_NAME")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "❌ Error: Required environment variables are not set:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

# Check if Docker services are running
if ! docker compose ps postgres | grep -q "Up"; then
    echo "❌ Error: PostgreSQL container is not running"
    echo "Start services with: docker compose up -d"
    exit 1
fi

echo "🚀 Starting database migration..."
echo "================================"

# URL-encode the password to handle special characters like @
ENCODED_PROD_DB_PASS=$(printf '%s' "${PROD_DB_PASS}" | jq -sRr @uri)

# Create migration.load with credentials (using heredoc without quotes to allow variable expansion)
cat > migration.load.tmp << EOF
LOAD DATABASE
  FROM mysql://${PROD_DB_USER}:${ENCODED_PROD_DB_PASS}@host.docker.internal:${LOCAL_TUNNEL_PORT}/${PROD_DB_NAME}
  INTO postgresql://moodleuser:moodlepass@postgres:5432/moodle

WITH
  include drop,
  create tables,
  create indexes,
  reset sequences,
  workers = 8,
  concurrency = 1

SET
  PostgreSQL PARAMETERS
    maintenance_work_mem to '512MB',
    work_mem to '128MB'

CAST
  type tinyint to boolean drop typemod using tinyint-to-boolean,
  type tinyint when (= precision 1) to boolean drop typemod using tinyint-to-boolean,
  type int with extra auto_increment to serial drop typemod drop default drop not null,
  type bigint with extra auto_increment to bigserial drop typemod drop default drop not null,
  type datetime to timestamp drop typemod,
  type longtext to text drop typemod,
  type mediumtext to text drop typemod,
  type tinytext to text drop typemod,
  type longblob to bytea drop typemod,
  type mediumblob to bytea drop typemod,
  type blob to bytea drop typemod

BEFORE LOAD DO
  \$\$ DROP SCHEMA IF EXISTS public CASCADE; \$\$,
  \$\$ CREATE SCHEMA public; \$\$;
EOF

# Set up SSH tunnel
echo "🔐 Setting up SSH tunnel to production database..."
ssh -M -S /tmp/migration_ssh_socket -fN -L ${LOCAL_TUNNEL_PORT}:localhost:${PROD_DB_PORT} ${PROD_SSH_USER}@${PROD_SSH_HOST}

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    ssh -S /tmp/migration_ssh_socket -O exit ${PROD_SSH_USER}@${PROD_SSH_HOST} 2>/dev/null || true
    rm -f /tmp/migration_ssh_socket
    rm -f migration.load.tmp
}
trap cleanup EXIT

echo "✅ SSH tunnel established on port ${LOCAL_TUNNEL_PORT}"
echo ""

# Wait for tunnel to be ready
sleep 2

# Test basic port connectivity
echo "🔍 Testing SSH tunnel connectivity..."
if ! nc -z localhost ${LOCAL_TUNNEL_PORT} 2>/dev/null; then
    echo "❌ Error: SSH tunnel not ready on port ${LOCAL_TUNNEL_PORT}"
    exit 1
fi
echo "✅ SSH tunnel ready"
echo ""

echo "📝 Database configuration:"
echo "   Source: mysql://${PROD_DB_USER}:***@host.docker.internal:${LOCAL_TUNNEL_PORT}/${PROD_DB_NAME}"
echo "   Target: postgresql://moodleuser:***@postgres:5432/moodle"
echo ""

echo "🔍 Checking generated migration config..."
head -5 migration.load.tmp
echo ""

# Run pgloader via Docker
echo "🔄 Starting pgloader migration..."
echo "This may take several minutes depending on database size..."
echo ""

# Check if we need to build pgloader image for ARM64
if ! docker image inspect elearning-pgloader:latest >/dev/null 2>&1; then
    echo "📦 Building pgloader Docker image for ARM64..."
    docker build -t elearning-pgloader:latest -f docker/pgloader/Dockerfile docker/pgloader/
    echo "✅ Image built successfully"
    echo ""
fi

docker run --rm \
    --network elearning-app_moodle_network \
    --add-host=host.docker.internal:host-gateway \
    -v "$(pwd)/migration.load.tmp:/work/migration.load" \
    elearning-pgloader:latest \
    /work/migration.load

echo ""
echo "✅ Migration complete!"
echo ""
echo "Next steps:"
echo "1. Visit http://localhost:8080"
echo "2. Complete Moodle installation"
echo "3. Login with migrated admin credentials"
