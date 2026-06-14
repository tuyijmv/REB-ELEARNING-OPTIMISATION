#!/bin/bash

#================================================================================
# Moodle Production-to-Dev SQL Migration Script
#
# This script connects to a production Moodle server via SSH to generate
# a lean, anonymized SQL dump suitable for a development environment.
# It exports the full DB schema, essential config tables, and a small
# sample of courses with their associated users and data.
#
# INSTRUCTIONS:
# 1. Copy .env.prod-migration.example to .env.prod-migration
# 2. Edit .env.prod-migration and fill in your production server credentials
# 3. Make the script executable: chmod +x create-dev-sql-dump.sh
# 4. Run the script: ./create-dev-sql-dump.sh
# 5. A file named 'dev_migration.sql' will be created in the current directory
#================================================================================

set -e # Exit immediately if a command exits with a non-zero status.

#================================================================================
#== CONFIGURATION
#================================================================================

# Load environment variables from .env.prod-migration if it exists
if [ -f .env.prod-migration ]; then
    echo "📋 Loading configuration from .env.prod-migration"
    set -a
    source .env.prod-migration
    set +a
fi

# --- Remote SSH & DB Credentials ---
PROD_SSH_USER="${PROD_SSH_USER:-root}"
PROD_SSH_HOST="${PROD_SSH_HOST}"
PROD_DB_USER="${PROD_DB_USER:-root}"
PROD_DB_PASS="${PROD_DB_PASS}"
PROD_DB_NAME="${PROD_DB_NAME}"
# Path to mariadb-dump on the production server (usually just 'mariadb-dump')
PROD_MARIADB_DUMP_CMD="${PROD_MARIADB_DUMP_CMD:-mariadb-dump}"

# --- Migration Settings ---
OUTPUT_SQL_FILE="${OUTPUT_SQL_FILE:-dev_migration.sql}"
COURSE_SAMPLE_SIZE=${COURSE_SAMPLE_SIZE:-5} # The number of courses to migrate
DEV_USER_PASSWORD="${DEV_USER_PASSWORD:-Password123!}" # Password for all users in the dev env
# --- Moodle Table Prefix ---
PREFIX="${PREFIX:-mdl_}"

# --- Validate required configuration ---
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
    echo ""
    echo "Please set these variables in your environment or create a .env.prod-migration file."
    echo "See .env.prod-migration.example for reference."
    exit 1
fi

# --- Tables to export with ALL their data (core config) ---
# (Table list remains the same, omitted for brevity)
TABLES_TO_DUMP_FULL=(
    "${PREFIX}config"
    "${PREFIX}config_plugins"
    "${PREFIX}course_categories"
    "${PREFIX}enrol"
    "${PREFIX}role"
    "${PREFIX}role_capabilities"
    "${PREFIX}role_context_levels"
    "${PREFIX}event"
    "${PREFIX}filter_active"
    "${PREFIX}filter_config"
    "${PREFIX}question_categories"
)

#================================================================================
#== SCRIPT LOGIC (No need to edit below this line)
#================================================================================

# <<< MODIFICATION: Define a temporary file for the SSH control socket
CONTROL_PATH="/tmp/ssh_mux_socket_$$"

# <<< MODIFICATION: Function to clean up the control socket on exit
function cleanup {
    echo "🚪 Closing persistent SSH connection..."
    ssh -S "${CONTROL_PATH}" -O exit "${PROD_SSH_USER}@${PROD_SSH_HOST}" 2>/dev/null
    rm -f "${CONTROL_PATH}"
}
trap cleanup EXIT

# --- SSH and DB command wrappers ---
# <<< MODIFICATION: Update SSH_CMD to use the control socket
SSH_CMD="ssh -S ${CONTROL_PATH} ${PROD_SSH_USER}@${PROD_SSH_HOST}"
MARIADB_CMD_BASE="${PROD_MARIADB_DUMP_CMD} -u${PROD_DB_USER} -p'${PROD_DB_PASS}' ${PROD_DB_NAME}"
MARIADB_QUERY_CMD="mariadb -u${PROD_DB_USER} -p'${PROD_DB_PASS}' ${PROD_DB_NAME} -sN"

echo "🚀 Starting Moodle DB migration script."
echo "----------------------------------------"

# <<< MODIFICATION: Start the persistent SSH connection in the background
echo "🔑 Establishing persistent SSH connection... (You will be prompted for your password once)"
ssh -M -S "${CONTROL_PATH}" -fN "${PROD_SSH_USER}@${PROD_SSH_HOST}"
echo "✅ Connection established."


# Clean up previous run
rm -f "$OUTPUT_SQL_FILE"
touch "$OUTPUT_SQL_FILE"

# --- 1. Dump the entire database schema (without data) ---
echo "📦 Step 1/6: Dumping database schema..."
$SSH_CMD "${MARIADB_CMD_BASE} --no-data" > "$OUTPUT_SQL_FILE"
echo "✅ Schema dumped."

# ... the rest of the script remains exactly the same ...
# ... from Step 2 through to the end ...

# --- 2. Dump full data for essential configuration tables ---
echo "⚙️  Step 2/6: Dumping full data for config tables..."
for table in "${TABLES_TO_DUMP_FULL[@]}"; do
    echo "    -> Dumping ${table}"
    $SSH_CMD "${MARIADB_CMD_BASE} ${table}" >> "$OUTPUT_SQL_FILE"
done
echo "✅ Config tables dumped."

# --- 3. Get IDs for sample data (courses and users) ---
echo "🔍 Step 3/6: Identifying sample data..."
COURSE_IDS=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SELECT id FROM ${PREFIX}course WHERE id > 1 ORDER BY id LIMIT ${COURSE_SAMPLE_SIZE};'")
COURSE_IDS_SQL_LIST=$(echo "$COURSE_IDS" | paste -s -d, -)
echo "    -> Migrating Course IDs: ${COURSE_IDS_SQL_LIST}"
CONTEXT_IDS=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SELECT id FROM ${PREFIX}context WHERE contextlevel=50 AND instanceid IN (${COURSE_IDS_SQL_LIST});'")
CONTEXT_IDS_SQL_LIST=$(echo "$CONTEXT_IDS" | paste -s -d, -)
ENROLLED_USER_IDS=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SELECT DISTINCT userid FROM ${PREFIX}role_assignments WHERE contextid IN (${CONTEXT_IDS_SQL_LIST});'")
ADMIN_USER_IDS=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SELECT userid FROM ${PREFIX}role_assignments ra JOIN ${PREFIX}role r ON ra.roleid = r.id WHERE r.shortname = \"manager\";'")
ALL_USER_IDS=$(echo -e "${ENROLLED_USER_IDS}\n${ADMIN_USER_IDS}" | sort -u)
USER_IDS_SQL_LIST=$(echo "$ALL_USER_IDS" | paste -s -d, -)
echo "    -> Migrating $(echo "$ALL_USER_IDS" | wc -w) users (enrolled users + admins)."
echo "✅ Sample data identified."

# --- 4. Dump subset of data based on the identified IDs ---
echo "📚 Step 4/6: Dumping subset of course and user data..."
TABLES_BY_COURSE_ID=( "${PREFIX}course" "${PREFIX}course_sections" "${PREFIX}course_modules" "${PREFIX}course_completions" "${PREFIX}context" )
for table in "${TABLES_BY_COURSE_ID[@]}"; do
    where_clause="id IN (${COURSE_IDS_SQL_LIST})"
    if [ "$table" == "${PREFIX}context" ]; then where_clause="id IN (${CONTEXT_IDS_SQL_LIST})"; elif [ "$table" != "${PREFIX}course" ]; then where_clause="course IN (${COURSE_IDS_SQL_LIST})"; fi
    echo "    -> Dumping ${table} for selected courses."
    $SSH_CMD "${MARIADB_CMD_BASE} ${table} --where=\"${where_clause}\"" >> "$OUTPUT_SQL_FILE"
done
TABLES_BY_USER_ID=( "${PREFIX}user" "${PREFIX}user_enrolments" "${PREFIX}role_assignments" )
for table in "${TABLES_BY_USER_ID[@]}"; do
    where_clause="userid IN (${USER_IDS_SQL_LIST})"
    if [ "$table" == "${PREFIX}user" ]; then
        where_clause="id IN (${USER_IDS_SQL_LIST})"
    elif [ "$table" == "${PREFIX}role_assignments" ]; then
        where_clause="userid IN (${USER_IDS_SQL_LIST}) OR contextid IN (${CONTEXT_IDS_SQL_LIST})"
    fi
    echo "    -> Dumping ${table} for selected users."
    $SSH_CMD "${MARIADB_CMD_BASE} ${table} --where=\"${where_clause}\"" >> "$OUTPUT_SQL_FILE"
done
MODULE_TABLES=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SELECT DISTINCT CONCAT(\"${PREFIX}\", name) FROM ${PREFIX}modules;'")
for table in $MODULE_TABLES; do
    HAS_COURSE_COL=$($SSH_CMD "${MARIADB_QUERY_CMD} -e 'SHOW COLUMNS FROM ${table} LIKE \"course\";'")
    if [ -n "$HAS_COURSE_COL" ]; then
        echo "    -> Dumping module table ${table} for selected courses."
        $SSH_CMD "${MARIADB_CMD_BASE} ${table} --where=\"course IN (${COURSE_IDS_SQL_LIST})\"" >> "$OUTPUT_SQL_FILE"
    fi
done
echo "    -> Dumping ${PREFIX}files for selected courses."
$SSH_CMD "${MARIADB_CMD_BASE} ${PREFIX}files --where=\"contextid IN (${CONTEXT_IDS_SQL_LIST})\"" >> "$OUTPUT_SQL_FILE"
echo "✅ Subset data dumped."

# --- 5. Append data anonymization queries ---
echo "🔒 Step 5/6: Appending data anonymization queries..."
DEV_PASSWORD_HASH=$(php -r "echo password_hash('${DEV_USER_PASSWORD}', PASSWORD_ARGON2ID);")
cat <<EOF >> "$OUTPUT_SQL_FILE"
-- Anonymization queries... (omitted for brevity)
-- -----------------------------------------------------------------------------
-- Data Anonymization and Cleanup
-- -----------------------------------------------------------------------------
LOCK TABLES \`${PREFIX}user\` WRITE;
UPDATE \`${PREFIX}user\` SET firstname = CONCAT('UserF', id), lastname = CONCAT('UserL', id), email = CONCAT('user', id, '@example.com'), phone1 = '', phone2 = '', address = '', city = 'MoodleVille', username = CONCAT('user', id), password = '${DEV_PASSWORD_HASH}', auth = 'manual', confirmed = 1, suspended = 0, lang = 'en', lastip = '127.0.0.1', picture = 0, description = 'Test user account.' WHERE id > 2;
UPDATE \`${PREFIX}user\` SET username = 'admin' WHERE id = 2;
UNLOCK TABLES;
TRUNCATE TABLE \`${PREFIX}logstore_standard_log\`;
EOF
echo "✅ Anonymization queries appended."

# --- 6. Finalization ---
echo "🏁 Step 6/6: Finalizing SQL file."
# (Finalizing code omitted for brevity, it is unchanged)
sed -i '' '1i\
SET a=1; -- Dummy command to satisfy some clients\
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;\
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;\
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;\
/*!40101 SET NAMES utf8 */;\
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;\
/*!40103 SET TIME_ZONE='\''+00:00'\'' */;\
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;\
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;\
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='\''NO_AUTO_VALUE_ON_ZERO'\'' */;\
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;\
' "$OUTPUT_SQL_FILE"
echo '
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
' >> "$OUTPUT_SQL_FILE"
echo "✅ SQL file finalized."
echo "----------------------------------------"
echo "🎉 Success! Your migration file is ready: ${OUTPUT_SQL_FILE}"
