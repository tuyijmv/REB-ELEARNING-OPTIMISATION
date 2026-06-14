# Database Migration Guide

This guide explains how to migrate your production Moodle database to the development environment using MariaDB.

## Current Setup

- **Production:** MariaDB/MySQL with Moodle 5.0.2
- **Development:** MariaDB 11.4 with Moodle 5.1
- **Migration approach:** SQL dump from production → Load into local MariaDB

## Prerequisites

- SSH access to production server
- Production database credentials
- Docker and Docker Compose installed locally
- At least 2GB free disk space

## Migration Method: SQL Dump

This is the recommended approach since both production and development use MariaDB.

### Steps

1. **Configure credentials:**
   ```bash
   cp .env.prod-migration.example .env.prod-migration
   nano .env.prod-migration  # Fill in production credentials
   ```

2. **Create SQL dump from production:**
   ```bash
   ./create-dev-sql-dump.sh
   ```

   This creates `dev_migration.sql` with:
   - Full schema
   - Essential config tables
   - Sample of N courses (default: 5)
   - Related users (anonymized)
   - Excludes log tables for smaller size

3. **Place dump for auto-loading:**
   ```bash
   cp dev_migration.sql docker/mariadb/initdb.d/01-migration.sql
   ```

4. **Start services (auto-loads migration):**
   ```bash
   docker compose down -v  # Remove existing database
   docker compose up -d    # Starts fresh, auto-loads SQL
   ```

5. **Run database upgrade:**
   ```bash
   docker compose exec php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive
   ```

6. **Access Moodle:**
   Visit http://localhost:8080
   - Username: `admin`
   - Password: `Admin123!` (or reset via CLI)

### What Gets Migrated

✅ Database schema (all tables)
✅ Configuration settings
✅ Courses (sampled - configurable)
✅ Users (anonymized)
✅ Roles and permissions
✅ Course content and activities
❌ Log tables (excluded for performance)
❌ Cache tables (excluded)
❌ Session data (excluded)

## Customizing the Migration

### Sample Specific Courses

In `.env.prod-migration`, set:
```bash
COURSE_SAMPLE_SIZE=10  # Number of courses to migrate
```

### Exclude Additional Tables

Edit `create-dev-sql-dump.sh` and add tables to exclude:
```bash
# Example: Exclude quiz attempts
EXCLUDE_TABLES="mdl_logstore_standard_log mdl_log mdl_sessions mdl_quiz_attempts"
```

## Post-Migration Steps

After migration, you may need to:

1. **Fix missing database records:**
   - System context, site course, default pages (automatically fixed during upgrade)

2. **Disable missing plugins:**
   ```bash
   # Remove plugins that don't exist in Moodle 5.1
   docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
     "DELETE FROM mdl_config_plugins WHERE plugin IN ('auth_externalid', 'auth_antihammer');"
   ```

3. **Update theme:**
   ```bash
   docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
     "UPDATE mdl_config SET value='boost' WHERE name='theme';"
   ```

4. **Purge caches:**
   ```bash
   docker compose exec php php /var/www/html/moodle_app/admin/cli/purge_caches.php
   ```

## Troubleshooting

### SSH Connection Issues

**Error: "SSH connection failed"**
- Verify SSH credentials: `ssh user@production-server`
- Check firewall rules on production server
- Ensure SSH key is added if using key-based auth

### Database Issues

**Error: "Can't find data record"**
- Run the database upgrade script
- Check that required tables exist
- See "Post-Migration Steps" above

**Error: "Authentication plugin not found"**
- Remove missing plugins from config:
  ```bash
  docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
    "UPDATE mdl_config SET value='manual,email' WHERE name='auth';"
  ```

### Migration Incomplete

**Some tables missing:**
- Check migration logs: `docker compose logs mariadb`
- Verify SQL file: `head -100 dev_migration.sql`
- Re-run migration from scratch

## Database Comparison

| Feature | Production | Development |
|---------|-----------|-------------|
| RDBMS | MariaDB 10.x | MariaDB 11.4 |
| Storage | InnoDB, ROW_FORMAT=COMPRESSED | InnoDB, default |
| Port | 3306 | 3306 (internal) |
| Users | Real data | Anonymized |
| Size | Full (~10GB+) | Sampled (~1GB) |
| Version | Moodle 5.0.2 | Moodle 5.1 |

## Full Database Migration

To migrate the entire production database without sampling:

1. **Create full dump on production:**
   ```bash
   ssh user@production-server
   mariadb-dump -u root -p moodle > full_dump.sql
   exit
   ```

2. **Copy to local machine:**
   ```bash
   scp user@production-server:full_dump.sql docker/mariadb/initdb.d/01-migration.sql
   ```

3. **Load into development:**
   ```bash
   docker compose down -v
   docker compose up -d
   ```

## Resetting Admin Password

If you can't log in:

```bash
docker compose exec php php /var/www/html/moodle_app/admin/cli/reset_password.php
```

Or manually:
```bash
# Generate password hash
docker compose exec php php -r "echo password_hash('NewPassword123!', PASSWORD_DEFAULT);"

# Update in database
docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
  "UPDATE mdl_user SET password='<hash-from-above>' WHERE username='admin';"
```

## Security Notes

⚠️ **Important:**
- Never commit `.env.prod-migration` (contains production credentials)
- Anonymize user data before sharing development databases
- Use VPN/secure connection when connecting to production
- Keep SSH keys secure
- Regularly rotate production database passwords
- **Check for backdoors/malware** - We found a malicious backdoor in production `mdl_config.aspellpath`

## Getting Help

- **Moodle database:** https://docs.moodle.org/en/Database
- **MariaDB:** https://mariadb.org/documentation/
- **Migration tools:** Check `create-dev-sql-dump.sh` and `run-migration.sh`

## Quick Reference

```bash
# Sampled migration (recommended for development)
./create-dev-sql-dump.sh
cp dev_migration.sql docker/mariadb/initdb.d/01-migration.sql
docker compose down -v && docker compose up -d

# Check migration status
docker compose logs mariadb | tail -50

# Connect to dev database
docker compose exec mariadb mariadb -u moodleuser -p moodle

# Run upgrade after migration
docker compose exec php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive

# Purge caches
docker compose exec php php /var/www/html/moodle_app/admin/cli/purge_caches.php

# Reset and try again
docker compose down -v
docker compose up -d
# Then re-run migration
```

## Known Issues & Fixes

### Missing System Records

After migration, you may need to create:

1. **System context** (required for Moodle to start)
2. **Site course** (course ID 1)
3. **Guest and admin users** (user IDs 1 and 2)
4. **Default "My" pages**
5. **Message processors**
6. **Default grading scale**

These are automatically created during the upgrade process if missing.

### Missing Plugins

Production plugins that don't exist in Moodle 5.1:
- `auth_externalid` - Remove from config
- `auth_antihammer` - Remove from config
- Theme `moove` - Change to `boost`

### Version Mismatch

Production runs Moodle 5.0.2, development runs 5.1. The upgrade script handles this automatically.
