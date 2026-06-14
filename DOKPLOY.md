# Dokploy Deployment Guide

This guide explains how to deploy the Moodle e-learning platform to Dokploy with separate services for staging and production environments.

## Architecture

The application is deployed as 4 independent services:

1. **MariaDB** - Database server (MariaDB 11.4)
2. **PHP-FPM** - Application server (PHP 8.2 + Moodle 5.1)
3. **Nginx** - Web server/reverse proxy
4. **MinIO** - S3-compatible object storage

## Branch Strategy

- **dev** branch → Staging environment (auto-deploys on PR merge)
- **main** branch → Production environment (manual deployment)

## Prerequisites

1. Dokploy account with GitHub integration enabled
2. GitHub repository connected to Dokploy
3. Domain/subdomain configured for staging (e.g., `staging.yourdomain.com`)
4. SSH private key with access to private repositories (if using private plugins)

## SSH Configuration for Private Repositories

This project includes a private plugin (`local_reblibrary`) that requires SSH authentication during Docker build. You need to configure SSH keys in Dokploy.

### Option 1: Using GitHub Deploy Key (Recommended)

1. **Generate a deploy key** (on your local machine):
   ```bash
   ssh-keygen -t ed25519 -C "dokploy-moodle-deploy" -f ~/.ssh/dokploy_moodle_deploy
   ```

2. **Add the public key to GitHub**:
   - Go to your private repository: https://github.com/REB-ICTE/local_reblibrary
   - Navigate to Settings → Deploy keys
   - Click "Add deploy key"
   - Paste the contents of `~/.ssh/dokploy_moodle_deploy.pub`
   - Name it "Dokploy Deploy Key"
   - Check "Allow read access" (write access not needed)
   - Click "Add key"

3. **Add the private key to Dokploy**:
   - In Dokploy dashboard, go to your project
   - Navigate to Settings or Build Configuration
   - Look for "SSH Keys" or "Build Secrets" section
   - Add the private key contents from `~/.ssh/dokploy_moodle_deploy`
   - Dokploy will mount this key during Docker builds using BuildKit secrets

### Option 2: Using Your Personal SSH Key

If you prefer to use your existing SSH key:

1. **Copy your private SSH key** (usually `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`)
2. **Add it to Dokploy** (same steps as above)

**Security Note:** Using a deploy key is more secure as it's limited to specific repositories and has read-only access.

### Verify SSH Configuration

After configuring, Dokploy will automatically:
- Mount your SSH key during build using `--mount=type=ssh`
- Add GitHub to known_hosts
- Clone private repositories using SSH URLs (e.g., `git@github.com:REB-ICTE/local_reblibrary.git`)

If the build fails with SSH errors, check:
1. The SSH key has access to the private repository
2. The key is properly configured in Dokploy
3. GitHub's SSH host key is trusted (done automatically by Dockerfile)

## Initial Setup

### 1. Create Dokploy Project

1. Log into Dokploy dashboard
2. Create a new project: "Moodle E-Learning"
3. Connect your GitHub repository
4. You'll create 4 separate services within this project

### 2. Service 1: MariaDB Database

**Configuration:**
- **Name:** `moodle-mariadb`
- **Type:** Docker
- **Branch:** `dev` (for staging)
- **Build Context:** `./docker/mariadb`
- **Dockerfile Path:** `Dockerfile`

**Environment Variables:**
```bash
MARIADB_DATABASE=moodle
MARIADB_USER=moodleuser
MARIADB_PASSWORD=<generate-secure-password>
MARIADB_ROOT_PASSWORD=<generate-secure-root-password>
```

**Volumes:**
- `/var/lib/mysql` → Named volume: `mariadb_data`

**Port Mapping:**
- Internal only (no external port needed)

**Health Check:**
- Command: `healthcheck.sh --connect --innodb_initialized`
- Interval: 10s
- Timeout: 5s
- Retries: 5

**Command:**
```bash
--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
```

---

### 3. Service 2: PHP-FPM Application

**Configuration:**
- **Name:** `moodle-php`
- **Type:** Docker
- **Branch:** `dev` (for staging)
- **Build Context:** `.` (root directory)
- **Dockerfile Path:** `docker/php/Dockerfile`

**Environment Variables:**
```bash
DB_TYPE=mariadb
DB_HOST=moodle-mariadb
DB_NAME=moodle
DB_USER=moodleuser
DB_PASSWORD=<same-as-mariadb-password>
DB_PORT=3306
DB_PREFIX=mdl_
MOODLE_WWWROOT=https://staging.yourdomain.com
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_DEBUG=false
MOODLE_MAIL_NOREPLY=noreply@yourdomain.com
MOODLE_MAIL_PREFIX=[Moodle Staging]
MOODLE_REVERSEPROXY=true
MOODLE_SSLPROXY=true
S3_ENDPOINT=http://moodle-minio:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=<generate-secure-minio-password>
S3_BUCKET=moodle
S3_REGION=us-east-1
```

**Volumes:**
- `/var/www/moodledata` → Named volume: `moodledata` (shared with Nginx)

**Port Mapping:**
- Internal only (port 9000 for FastCGI)

**Dependencies:**
- Depends on: `moodle-mariadb` (must be healthy before starting)

**Build Time:** ~5-10 minutes (clones Moodle core + plugins)

**SSH Requirements:**
- This service clones a private plugin (`local_reblibrary`) during build
- Requires SSH key configured in Dokploy (see "SSH Configuration for Private Repositories" section above)
- Uses Docker BuildKit with `--mount=type=ssh` to securely access private repositories

---

### 4. Service 3: Nginx Web Server

**Configuration:**
- **Name:** `moodle-nginx`
- **Type:** Docker
- **Branch:** `dev` (for staging)
- **Build Context:** `./docker/nginx`
- **Dockerfile Path:** `Dockerfile`

**Environment Variables:**
```bash
PHP_FPM_HOST=moodle-php
NGINX_PORT=8080
```

**Notes:**
- `PHP_FPM_HOST`: PHP-FPM service hostname (must match your PHP service name)
- `NGINX_PORT`: Port nginx listens on inside the container (default: 8080)

**Volumes:**
- `/var/www/moodledata` → Named volume: `moodledata` (shared with PHP, read-only)

**Port Mapping:**
- `8080:8080` (or configure Dokploy's built-in reverse proxy)
- Can be customized via `NGINX_PORT` environment variable

**Dependencies:**
- Depends on: `moodle-php`

**Domain Configuration:**
- Configure custom domain in Dokploy: `staging.yourdomain.com`
- Enable SSL/TLS via Dokploy's Let's Encrypt integration

**Health Check:**
- Command: `wget --quiet --tries=1 --spider http://localhost/nginx-health || exit 1`
- Interval: 30s
- Timeout: 3s
- Retries: 3

---

### 5. Service 4: MinIO Object Storage

**Configuration:**
- **Name:** `moodle-minio`
- **Type:** Docker (use official image)
- **Branch:** `dev` (for staging)
- **Image:** `minio/minio:latest`

**Environment Variables:**
```bash
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=<generate-secure-minio-password>
MINIO_REGION_NAME=us-east-1
```

**Volumes:**
- `/data` → Named volume: `minio_data`
- `./docker/minio/init.sh:/docker-entrypoint-initdb.d/init.sh:ro` (mount initialization script)

**Port Mapping:**
- `9000:9000` (API - internal only)
- `9001:9001` (Console - optional, can be external for admin access)

**Command:**
```bash
server /data --console-address ":9001"
```

**Health Check:**
- Command: `curl -f http://localhost:9000/minio/health/live`
- Interval: 30s
- Timeout: 10s
- Retries: 3

---

## Service Networking

Dokploy automatically creates an internal network for all services in the project. Services communicate using their service names as hostnames:

- **Database:** `moodle-mariadb:3306`
- **PHP-FPM:** `moodle-php:9000`
- **Nginx:** `moodle-nginx:80`
- **MinIO:** `moodle-minio:9000`

## Deployment Order

Services must start in this order:
1. MariaDB (wait for healthy)
2. MinIO (can start in parallel with step 1)
3. PHP-FPM (depends on MariaDB being healthy)
4. Nginx (depends on PHP-FPM)

Configure dependencies in Dokploy to ensure proper startup order.

## Volume Management

Create these named volumes in Dokploy:

1. **mariadb_data** - Database files (persistent)
2. **moodledata** - Moodle data directory (shared between PHP and Nginx)
3. **minio_data** - Object storage files (persistent)

**Important:** The `moodledata` volume must be mounted to both PHP-FPM and Nginx services.

## Initial Deployment Steps

### First Time Setup

1. **Deploy all 4 services** in order (MariaDB → MinIO → PHP → Nginx)

2. **Wait for services to be healthy**
   - Check Dokploy logs for each service
   - Verify MariaDB initialized successfully
   - Verify PHP-FPM completed Moodle build

3. **Access Moodle installation**
   - Visit `https://staging.yourdomain.com`
   - Moodle should auto-configure from environment variables
   - If installation wizard appears, follow prompts (should be pre-configured)

4. **Initial database setup**
   - If using a fresh database, Moodle will create tables automatically
   - If migrating data, see "Database Migration" section below

5. **Set up admin account**
   - Default admin credentials from migration: `admin` / `Admin123!`
   - Or create new admin during first-time setup

6. **Clear caches**
   - SSH into PHP container: `docker exec -it moodle-php bash`
   - Run: `php /var/www/html/moodle_app/admin/cli/purge_caches.php`

### Verify Deployment

Check each service:

```bash
# Check MariaDB
docker exec moodle-mariadb mariadb -u moodleuser -p<password> -e "SHOW DATABASES;"

# Check PHP-FPM
docker exec moodle-php php --version

# Check Moodle installation
docker exec moodle-php ls -la /var/www/html/moodle_app

# Check Nginx
curl -I https://staging.yourdomain.com

# Check MinIO
curl http://<minio-host>:9001
```

## Database Migration

To migrate production data to staging:

1. **Create SQL dump from production** (run locally):
   ```bash
   # Configure .env.prod-migration with production credentials
   cp .env.prod-migration.example .env.prod-migration
   ./create-dev-sql-dump.sh
   ```

2. **Upload dump to Dokploy server**

3. **Import into MariaDB service**:
   ```bash
   docker exec -i moodle-mariadb mariadb -u root -p<root-password> moodle < migration.sql
   ```

4. **Run Moodle upgrade**:
   ```bash
   docker exec moodle-php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive
   ```

## Continuous Deployment

### Automatic Staging Deployment

1. **Create PR to `dev` branch**
2. **Merge PR** → Dokploy automatically rebuilds and redeploys services
3. **Monitor deployment** in Dokploy dashboard
4. **Verify staging environment** after deployment completes

### Production Deployment

1. **Test thoroughly on staging**
2. **Create PR from `dev` to `main`**
3. **Merge to `main`** (does NOT auto-deploy)
4. **Manually trigger production deployment** in Dokploy
5. **Run database backup before deployment**

## Monitoring & Logs

### Access Service Logs

In Dokploy dashboard:
- Navigate to each service
- View real-time logs
- Filter by severity

### SSH into Containers

```bash
# PHP-FPM
docker exec -it moodle-php bash

# MariaDB
docker exec -it moodle-mariadb bash

# Nginx
docker exec -it moodle-nginx sh
```

### Common Commands

```bash
# Purge Moodle caches
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/purge_caches.php

# Database upgrade
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive

# Check Moodle version
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/version.php

# Reset admin password
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/reset_password.php

# Access MariaDB CLI
docker exec -it moodle-mariadb mariadb -u moodleuser -p moodle
```

## Troubleshooting

### Service Won't Start

1. Check Dokploy logs for specific error
2. Verify all environment variables are set correctly
3. Ensure dependent services are healthy
4. Check volume mounts are configured correctly

### Database Connection Errors

1. Verify MariaDB service is healthy
2. Check DB_HOST matches MariaDB service name
3. Verify credentials match between PHP and MariaDB services
4. Test connection: `docker exec moodle-php php -r "echo new mysqli('moodle-mariadb', 'moodleuser', 'password', 'moodle')->connect_error;"`

### Nginx 502 Bad Gateway or "host not found in upstream"

If you see errors like `host not found in upstream "php"`:

1. **Set PHP_FPM_HOST environment variable** in Nginx service:
   - Go to Nginx service settings in Dokploy
   - Add environment variable: `PHP_FPM_HOST=moodle-php`
   - The value must match your PHP service name exactly

2. **Check PHP-FPM is running**: `docker ps | grep moodle-php`

3. **Verify service names match**:
   - PHP service name in Dokploy: `moodle-php`
   - PHP_FPM_HOST in Nginx: `moodle-php`
   - These must be identical

4. **Check PHP-FPM logs**: `docker logs moodle-php`

5. **Restart Nginx service** after adding the environment variable

### File Permission Issues

1. Ensure moodledata volume has correct permissions (777 in development, 770 in production)
2. Check PHP container runs as www-data user
3. Verify entrypoint script sets permissions correctly

### Build Failures

1. **PHP build timeout**: Increase build timeout in Dokploy settings (build.sh takes ~5 min)
2. **Git clone failures**: Check GitHub access, ensure repository is public or SSH keys configured
3. **Out of memory**: Increase container memory limits in Dokploy

### SSH Authentication Errors

If you see errors like "fatal: could not read Username" or "Permission denied (publickey)":

1. **Verify SSH key is configured in Dokploy**:
   - Check Dokploy project settings for SSH keys section
   - Ensure the private key is properly added

2. **Verify deploy key has access**:
   - Go to https://github.com/REB-ICTE/local_reblibrary/settings/keys
   - Ensure your deploy key is listed and enabled

3. **Check SSH URL format**:
   - Private repos must use SSH format: `git@github.com:REB-ICTE/local_reblibrary.git`
   - Not HTTPS format: `https://github.com/REB-ICTE/local_reblibrary.git`
   - Verify in `moodle-config.json`

4. **Test SSH access locally**:
   ```bash
   ssh -T git@github.com
   # Should respond: "Hi username! You've successfully authenticated..."
   ```

5. **BuildKit not enabled**:
   - Ensure Dokploy has BuildKit enabled (should be default)
   - Check build logs for `# syntax=docker/dockerfile:1` at the top

## Security Considerations

### Production Checklist

Before deploying to production:

- [ ] Change all default passwords
- [ ] Use strong, randomly generated passwords
- [ ] Enable MOODLE_SSLPROXY=true
- [ ] Set MOODLE_REVERSEPROXY=true
- [ ] Disable debug mode (MOODLE_DEBUG=false)
- [ ] Configure proper email settings
- [ ] Set up database backups (automated snapshots)
- [ ] Configure volume backups for moodledata and minio_data
- [ ] Review and remove the malicious backdoor in mdl_config.aspellpath (see CLAUDE.md)
- [ ] Enable rate limiting on Nginx
- [ ] Configure fail2ban or similar brute force protection
- [ ] Set up monitoring and alerting
- [ ] Restrict MinIO console access (port 9001)
- [ ] Use separate credentials for production and staging

### Known Security Issues

⚠️ **CRITICAL:** Production database contains a malicious backdoor in `mdl_config.aspellpath`. See CLAUDE.md for details. Clean before production deployment:

```sql
UPDATE mdl_config SET value = '/usr/bin/aspell' WHERE name = 'aspellpath';
```

## Backup & Recovery

### Automated Backups

Configure in Dokploy:
1. **Database backups**: Daily snapshots of `mariadb_data` volume
2. **File backups**: Daily snapshots of `moodledata` and `minio_data` volumes
3. **Retention**: Keep 7 daily, 4 weekly, 3 monthly backups

### Manual Backup

```bash
# Backup database
docker exec moodle-mariadb mariadb-dump -u root -p<password> moodle > backup.sql

# Backup moodledata (from host)
tar -czf moodledata-backup.tar.gz /path/to/dokploy/volumes/moodledata

# Backup MinIO data
docker exec moodle-minio mc mirror myminio/moodle /backup/minio
```

### Recovery

1. Stop all services in Dokploy
2. Restore volumes from snapshots
3. Or restore from manual backup:
   ```bash
   # Restore database
   docker exec -i moodle-mariadb mariadb -u root -p<password> moodle < backup.sql

   # Restore files
   tar -xzf moodledata-backup.tar.gz -C /path/to/dokploy/volumes/
   ```
4. Start services in correct order
5. Verify data integrity

## Performance Optimization

### PHP-FPM Tuning

Add to `docker/php/Dockerfile`:
```dockerfile
RUN echo "pm.max_children = 50" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.start_servers = 10" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.min_spare_servers = 5" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.max_spare_servers = 15" >> /usr/local/etc/php-fpm.d/www.conf
```

### Nginx Caching

Already configured in `docker/nginx/default.conf`:
- Static files cached for 30 days
- Gzip compression enabled
- FastCGI buffers optimized

### Database Optimization

Add to MariaDB configuration:
```ini
innodb_buffer_pool_size = 2G
query_cache_size = 128M
tmp_table_size = 64M
max_heap_table_size = 64M
```

## Scaling

### Horizontal Scaling

To scale PHP-FPM service:
1. In Dokploy, increase replica count for `moodle-php` service
2. Dokploy load balances across replicas automatically
3. Ensure session storage uses database (not PHP files)

### Vertical Scaling

Increase resources per service:
- **MariaDB**: 2-4 CPU cores, 4-8GB RAM
- **PHP-FPM**: 2-4 CPU cores, 2-4GB RAM per replica
- **Nginx**: 1-2 CPU cores, 1-2GB RAM
- **MinIO**: 1-2 CPU cores, 2-4GB RAM

## Support

For issues:
1. Check Dokploy documentation: https://docs.dokploy.com
2. Review Moodle docs: https://docs.moodle.org
3. Check service logs in Dokploy dashboard
4. See CLAUDE.md for development guidance
5. See DOCKER.md for local Docker setup
