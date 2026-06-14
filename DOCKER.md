# Docker Setup for Moodle

This setup uses Docker Compose with MariaDB, PHP-FPM, and Nginx.

## Prerequisites

- Docker
- Docker Compose
- Git
- jq (for build.sh)

## Quick Start

1. **Configure environment** (optional):
   ```bash
   cp .env.example .env
   # Edit .env to customize settings (database credentials, port, etc.)
   ```

2. **Build Docker image**:
   ```bash
   docker compose build
   ```

   This will automatically:
   - Clone Moodle core and plugins (via `build.sh`)
   - Install system dependencies (git, jq, PHP extensions)
   - Configure PHP and Nginx

3. **Start Docker containers**:
   ```bash
   docker compose up -d
   ```

   The entrypoint script will automatically:
   - Create and set permissions for `/var/www/moodledata`
   - Copy `config.php.docker` to `moodle_app/config.php` (if not exists)

4. **Install Moodle dependencies**:
   ```bash
   docker compose exec php composer install -d /var/www/html/moodle_app
   ```

5. **Install Moodle database**:
   ```bash
   docker compose exec php php /var/www/html/moodle_app/admin/cli/install_database.php \
     --lang=en --adminpass=Admin123! --agree-license \
     --fullname="Moodle Site" --shortname="Moodle"
   ```

6. **Access Moodle**:
   - URL: http://localhost:8080
   - Username: `admin`
   - Password: `Admin123!` (or whatever you set in step 5)

**Note**: Moodle code is now baked into the Docker image. To update Moodle version or plugins:
1. Edit `config.json`
2. Rebuild the image: `docker compose build --no-cache php`
3. Restart: `docker compose up -d`

## Useful Commands

```bash
# View logs
docker compose logs -f

# Stop containers
docker compose down

# Stop and remove volumes (DELETES DATA)
docker compose down -v

# Restart a service
docker compose restart php

# Access PHP container shell
docker compose exec php bash

# Access MariaDB
docker compose exec mariadb mariadb -u moodleuser -p moodle
# Password: moodlepass (or what you set in .env)

# Database backup
docker compose exec mariadb mariadb-dump -u root -p moodle > backup_$(date +%Y%m%d).sql

# Database restore
docker compose exec -T mariadb mariadb -u root -p moodle < backup.sql

# Run Grunt commands
docker compose exec php npx grunt -C /var/www/html/moodle_app

# Run PHPUnit tests
docker compose exec php vendor/bin/phpunit -c /var/www/html/moodle_app
```

## Services

- **nginx**: Web server (port 8080)
- **php**: PHP-FPM 8.2
- **mariadb**: MariaDB 11.4

## Volumes

- `mariadb_data`: MariaDB database files
- `moodledata`: Moodle data directory (uploaded files, cache, etc.)

## Configuration

The `config.php.docker` file uses environment variables from `.env` file. Edit `.env` to customize:

**Database**:
- `DB_TYPE`: Database type (default: mariadb)
- `DB_HOST`: Database host (default: mariadb)
- `DB_PORT`: Database port (default: 3306)
- `DB_NAME`: Database name (default: moodle)
- `DB_USER`: Database user (default: moodleuser)
- `DB_PASSWORD`: Database password (default: moodlepass)
- `DB_ROOT_PASSWORD`: MariaDB root password (default: rootpass)
- `DB_PREFIX`: Database table prefix (default: mdl_)

**Moodle**:
- `MOODLE_PROTOCOL`: Protocol (http or https, default: http)
- `MOODLE_HOST`: Hostname (default: localhost)
- `MOODLE_PORT`: Port number (default: 8080)
- `MOODLE_WWWROOT`: (Optional) Full site URL - automatically constructed from above if not set
- `MOODLE_DEBUG`: Enable debugging mode (true/false, default: false)
- `MOODLE_MAIL_NOREPLY`: No-reply email address
- `MOODLE_MAIL_PREFIX`: Email subject prefix
- `MOODLE_REVERSEPROXY`: Enable if behind reverse proxy (true/false)
- `MOODLE_SSLPROXY`: Enable if reverse proxy handles SSL (true/false)

**Note**: `MOODLE_WWWROOT` is automatically constructed from `MOODLE_PROTOCOL`, `MOODLE_HOST`, and `MOODLE_PORT`. For standard ports (80/443), the port is omitted from the URL. The `MOODLE_PORT` also determines the host port for Nginx.

## Switching Databases

To switch to PostgreSQL:

1. Add PostgreSQL service to `docker-compose.yml`
2. Update `.env`:
   ```bash
   DB_TYPE=pgsql
   DB_HOST=postgres
   DB_PORT=5432
   ```
3. Restart services:
   ```bash
   docker compose down
   docker compose up -d
   ```

## Loading Production Data

To load a production database dump:

1. Place your SQL dump in `docker/mariadb/initdb.d/`:
   ```bash
   cp production_dump.sql docker/mariadb/initdb.d/01-migration.sql
   ```

2. Recreate the database:
   ```bash
   docker compose down -v
   docker compose up -d
   ```

The SQL file will be automatically imported on first start.

## Troubleshooting

**Permission issues**:
Permissions are set automatically on container startup. If you still have issues, manually fix them:
```bash
docker compose exec -u root php chown -R www-data:www-data /var/www/moodledata
docker compose restart php
```

**Database connection failed**:
- Check if mariadb service is healthy: `docker compose ps`
- Verify database credentials in .env
- Check MariaDB logs: `docker compose logs mariadb`

**PHP errors**:
- Check PHP logs: `docker compose logs php`
- Check Nginx logs: `docker compose logs nginx`

**MariaDB won't start**:
- Check logs: `docker compose logs mariadb`
- Ensure ports aren't in use: `docker compose ps`
- Try rebuilding: `docker compose build mariadb`
