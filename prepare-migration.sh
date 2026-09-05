#!/bin/bash

#================================================================================
# Prepare Migration SQL for PostgreSQL
#
# This script prepares the dev_migration.sql file (generated from MariaDB/MySQL)
# for loading into PostgreSQL by converting incompatible syntax.
#
# USAGE:
#   ./prepare-migration.sh [input_file] [output_file]
#
# DEFAULTS:
#   input_file: dev_migration.sql
#   output_file: docker/postgres/initdb.d/01-migration.sql
#
# IMPORTANT:
# - Place the converted SQL in docker/postgres/initdb.d/
# - Remove existing PostgreSQL data: docker compose down -v
# - Start fresh: docker compose up -d
# - PostgreSQL will automatically execute SQL files in initdb.d/ on first init
#================================================================================

set -e

INPUT_FILE="${1:-dev_migration.sql}"
OUTPUT_FILE="${2:-docker/postgres/initdb.d/01-migration.sql}"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file '$INPUT_FILE' not found."
    echo ""
    echo "Please run ./create-dev-sql-dump.sh first to generate the migration file."
    exit 1
fi

echo "🔄 Converting MySQL/MariaDB dump to PostgreSQL format..."
echo "   Input:  $INPUT_FILE"
echo "   Output: $OUTPUT_FILE"

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Perform basic MySQL to PostgreSQL conversions
# Note: This is a basic conversion. For complex migrations, consider using pgloader.
cat "$INPUT_FILE" | \
    # Remove MySQL-specific comments and pragmas
    sed '/^\/\*![0-9]\{5\}/d' | \
    sed '/^SET @OLD_/d' | \
    sed '/^SET @OLD_/d' | \
    sed 's/ENGINE=InnoDB//g' | \
    sed 's/DEFAULT CHARSET=[a-zA-Z0-9_]*//g' | \
    sed 's/COLLATE=[a-zA-Z0-9_]*//g' | \
    sed 's/AUTO_INCREMENT=[0-9]*//g' | \
    # Convert backticks to double quotes for identifiers
    sed "s/\`/\"/g" | \
    # Convert LOCK/UNLOCK TABLES (PostgreSQL doesn't need explicit locks in dumps)
    sed 's/^LOCK TABLES/-- LOCK TABLES/g' | \
    sed 's/^UNLOCK TABLES/-- UNLOCK TABLES/g' | \
    # Convert MySQL data types to PostgreSQL equivalents
    sed 's/ tinyint(1)/ SMALLINT/g' | \
    sed 's/ tinyint([0-9]*)/ SMALLINT/g' | \
    sed 's/ bigint([0-9]*)/ BIGINT/g' | \
    sed 's/ int([0-9]*)/ INTEGER/g' | \
    sed 's/ datetime/ TIMESTAMP/g' | \
    sed 's/ longtext/ TEXT/g' | \
    sed 's/ mediumtext/ TEXT/g' | \
    sed 's/ longblob/ BYTEA/g' | \
    sed 's/ mediumblob/ BYTEA/g' | \
    sed 's/ blob/ BYTEA/g' | \
    # Remove unsigned keyword (PostgreSQL doesn't have unsigned)
    sed 's/ unsigned//g' | \
    # Convert double quotes in strings back to single quotes
    sed "s/\\\'/'/g" \
    > "$OUTPUT_FILE"

echo "✅ Conversion complete!"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   1. This is a basic conversion. Complex schemas may need manual adjustments."
echo "   2. Review the output file for any conversion issues."
echo "   3. To load the migration:"
echo "      - Stop containers: docker compose down"
echo "      - Remove volumes:  docker compose down -v"
echo "      - Start fresh:     docker compose up -d"
echo "   4. PostgreSQL will execute files in initdb.d/ alphabetically on first startup."
echo ""
echo "📋 Alternative: For complex migrations, consider using pgloader:"
echo "   https://github.com/dimitri/pgloader"
