# Dokploy Quick Start Guide

## TL;DR - What You Need to Do

1. **Connect your GitHub repo to Dokploy**
2. **Configure SSH key** for private repository access (see below)
3. **Create 4 services** in Dokploy (see table below)
4. **Configure environment variables** from `.env.staging`
5. **Set up volumes** (3 named volumes)
6. **Deploy services** in order: MariaDB → MinIO → PHP → Nginx

## IMPORTANT: SSH Key Setup

This project includes a **private plugin** (`local_reblibrary`) that requires SSH authentication during build.

**Before deploying**, you MUST:
1. Generate a deploy key: `ssh-keygen -t ed25519 -C "dokploy-deploy" -f ~/.ssh/dokploy_deploy`
2. Add the public key (`~/.ssh/dokploy_deploy.pub`) to GitHub:
   - Go to https://github.com/REB-ICTE/local_reblibrary/settings/keys
   - Add deploy key with read access
3. Add the private key to Dokploy:
   - In your Dokploy project settings
   - Look for "SSH Keys" or "Build Secrets"
   - Paste the contents of `~/.ssh/dokploy_deploy`

**Without SSH configured, the PHP service build will fail!**

See `DOKPLOY.md` (SSH Configuration section) for detailed instructions.

## Service Configuration Table

| Service | Build Context | Dockerfile | Volumes | Ports | Dependencies |
|---------|---------------|------------|---------|-------|--------------|
| **moodle-mariadb** | `./docker/mariadb` | `Dockerfile` | `mariadb_data:/var/lib/mysql` | Internal only | None |
| **moodle-php** | `.` (root) | `docker/php/Dockerfile` | `moodledata:/var/www/moodledata` | Internal (9000) | mariadb (healthy) |
| **moodle-nginx** | `./docker/nginx` | `Dockerfile` | `moodledata:/var/www/moodledata:ro` | 80:80 | php |
| **moodle-minio** | Use image: `minio/minio:latest` | N/A | `minio_data:/data` | 9000, 9001 | None |

## Environment Variables by Service

### Service 1: moodle-mariadb
```bash
MARIADB_DATABASE=moodle
MARIADB_USER=moodleuser
MARIADB_PASSWORD=<generate-secure-password>
MARIADB_ROOT_PASSWORD=<generate-secure-root-password>
```

### Service 2: moodle-php
```bash
DB_TYPE=mariadb
DB_HOST=moodle-mariadb
DB_NAME=moodle
DB_USER=moodleuser
DB_PASSWORD=<same-as-mariadb>
DB_PORT=3306
DB_PREFIX=mdl_
MOODLE_WWWROOT=https://staging.yourdomain.com
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_DEBUG=false
MOODLE_REVERSEPROXY=true
MOODLE_SSLPROXY=true
S3_ENDPOINT=http://moodle-minio:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=<generate-secure-password>
S3_BUCKET=moodle
S3_REGION=us-east-1
```

### Service 3: moodle-nginx
```bash
PHP_FPM_HOST=moodle-php
NGINX_PORT=8080
```
**Important:**
- `PHP_FPM_HOST` must match your PHP service name!
- `NGINX_PORT` sets the port nginx listens on (default: 8080)

### Service 4: moodle-minio
```bash
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=<generate-secure-password>
MINIO_REGION_NAME=us-east-1
```

**Command:** `server /data --console-address ":9001"`

## Branch Strategy

- **`dev` branch** → Auto-deploys to staging when PR is merged
- **`main` branch** → Manual production deployment

## Step-by-Step Setup in Dokploy

### 1. Create Project
- Project name: "Moodle E-Learning"
- Connect GitHub repo

### 2. Add Service 1 (MariaDB)
- Name: `moodle-mariadb`
- Type: Docker
- Branch: `dev`
- Build context: `./docker/mariadb`
- Dockerfile: `Dockerfile`
- Add environment variables (see above)
- Add volume: `mariadb_data` → `/var/lib/mysql`
- Command: `--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`

### 3. Add Service 2 (PHP-FPM)
- Name: `moodle-php`
- Type: Docker
- Branch: `dev`
- Build context: `.` (root)
- Dockerfile: `docker/php/Dockerfile`
- Add environment variables (see above)
- Add volume: `moodledata` → `/var/www/moodledata`
- Depends on: `moodle-mariadb`

### 4. Add Service 3 (Nginx)
- Name: `moodle-nginx`
- Type: Docker
- Branch: `dev`
- Build context: `./docker/nginx`
- Dockerfile: `Dockerfile`
- Add volume: `moodledata` → `/var/www/moodledata` (read-only)
- Port: `80:80`
- Domain: Configure `staging.yourdomain.com`
- SSL: Enable Let's Encrypt
- Depends on: `moodle-php`

### 5. Add Service 4 (MinIO)
- Name: `moodle-minio`
- Type: Docker
- Image: `minio/minio:latest`
- Branch: `dev`
- Add environment variables (see above)
- Add volume: `minio_data` → `/data`
- Ports: `9000:9000`, `9001:9001`
- Command: `server /data --console-address ":9001"`

## First Deployment

1. **Deploy in order**: MariaDB → MinIO → PHP → Nginx
2. **Wait for builds** (PHP takes ~5-10 minutes)
3. **Check logs** for each service
4. **Visit** `https://staging.yourdomain.com`
5. **Complete Moodle setup** (should auto-configure)

## Common Commands

Access service containers:
```bash
# PHP-FPM
docker exec -it moodle-php bash

# MariaDB
docker exec -it moodle-mariadb bash

# Nginx
docker exec -it moodle-nginx sh
```

Useful Moodle commands:
```bash
# Purge caches
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/purge_caches.php

# Upgrade database
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/upgrade.php --non-interactive

# Reset admin password
docker exec moodle-php php /var/www/html/moodle_app/admin/cli/reset_password.php
```

## Continuous Deployment

**Staging (Automatic):**
1. Create PR to `dev` branch
2. Merge PR
3. Dokploy auto-deploys to staging
4. Monitor deployment in Dokploy dashboard

**Production (Manual):**
1. Test on staging
2. Merge `dev` → `main`
3. Manually trigger production deployment in Dokploy

## Troubleshooting

**Build fails with "fatal: could not read Username" or "Permission denied":**
- SSH key not configured in Dokploy
- Deploy key not added to GitHub repository
- Verify private key is correctly pasted in Dokploy
- See DOKPLOY.md "SSH Authentication Errors" section

**Build fails (other reasons):**
- Check build logs in Dokploy
- Verify all files are committed to `dev` branch
- Ensure build timeout is at least 10 minutes

**Service won't start:**
- Check dependencies are configured
- Verify environment variables are set
- Check service logs

**Database connection error:**
- Verify MariaDB is healthy before PHP starts
- Check DB_HOST matches MariaDB service name
- Verify credentials match

**502 Bad Gateway or "host not found in upstream":**
- **Set `PHP_FPM_HOST=moodle-php` in Nginx service environment variables**
- Verify PHP service name matches exactly
- Check PHP-FPM is running
- Restart Nginx after adding the environment variable

## Need More Details?

See `DOKPLOY.md` for comprehensive documentation including:
- Database migration guide
- Security checklist
- Backup & recovery
- Performance optimization
- Scaling strategies

## Support

- Dokploy docs: https://docs.dokploy.com
- Moodle docs: https://docs.moodle.org
- Project setup: See `CLAUDE.md` and `DOCKER.md`
