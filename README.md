# REB E-Learning Optimisation

A production-ready, fully automated Moodle 5.1 stack deployable on any fresh Ubuntu 22.04/24.04 VM via a single command, with built-in support for cloud auto-scaling (Terraform + Ansible).

## Architecture

```
                            +-------------------+
                            |   Load Balancer   |
                            |  (Nginx/ALB/ELB)  |
                            +--------+----------+
                                     |
                    +----------------+------------------+
                    |                 |                  |
            +-------+-------+ +-------+-------+ +------+------+
            |  App Server   | |  App Server   | |  App Server  |
            |  (Nginx+PHP)  | |  (Nginx+PHP)  | | (Nginx+PHP)  |
            +-------+-------+ +-------+-------+ +------+------+
                    |                 |                  |
                    +--------+--------+------------------+
                             |
            +----------------+------------------+
            |                |                  |
      +-----+------+ +------+------+ +--------+---------+
      |  Redis      | |  MinIO       | |  MySQL 8.4 RDS   |
      |  (Sessions) | |  (File Store)| |  (Managed DB)    |
      +-------------+ +--------------+ +------------------+
```

### Components

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Web Server** | Nginx Alpine | Reverse proxy, static file caching, SSL termination |
| **Application** | PHP 8.2-FPM | Moodle 5.1 runtime with OPcache |
| **Database** | MySQL 8.4 | Primary data store (replaces MariaDB) |
| **Cache/Sessions** | Redis 7 | Session storage and application cache |
| **File Storage** | MinIO / S3 | Moodledata on S3-compatible storage |
| **Orchestration** | Docker Compose | Local development and deployment |

## Quick Start

### One-Line Install

```bash
wget -qO reb https://raw.githubusercontent.com/tuyijmv/REB-ELEARNING-OPTIMISATION/main/reb && sudo bash reb --local
```

### What It Does

1. Detects OS (Ubuntu 22.04/24.04)
2. Installs Docker and docker-compose plugin
3. Installs `git`, `jq`, `curl`
4. Clones this repository to `/opt/reb-elearning-optimisation`
5. Creates `.env` with auto-selected port (8080-8090)
6. Runs `./build.sh` to clone Moodle 5.1 core
7. Starts all services with `docker compose up -d`
8. Waits for MySQL health check
9. Runs `composer install` inside PHP container
10. Executes Moodle CLI installer automatically
11. Configures Redis session handler
12. Outputs final URL and credentials

### Access

- **URL:** `http://localhost:<auto-port>` (e.g., `http://localhost:8080`)
- **Username:** `admin`
- **Password:** `admin@123`

### Post-Install

```bash
cd /opt/reb-elearning-optimisation

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d

# Run Moodle CLI
docker compose exec php php /var/www/html/moodle_app/admin/cli/something.php
```

## Local Docker Deployment

### Prerequisites

- Ubuntu 22.04 or 24.04
- sudo access
- Internet connection

### Manual Setup

```bash
# Clone repository
git clone https://github.com/tuyijmv/REB-ELEARNING-OPTIMISATION.git
cd REB-ELEARNING-OPTIMISATION

# Copy environment file
cp .env.example .env

# Build Moodle
chmod +x build.sh
./build.sh

# Start services
docker compose up -d
```

### Environment Variables

Key variables in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MOODLE_PORT` | `8080` | Host port for Nginx |
| `DB_TYPE` | `mysql` | Database driver |
| `DB_HOST` | `mysql` | Database hostname |
| `DB_NAME` | `moodle` | Database name |
| `DB_USER` | `moodleuser` | Database user |
| `DB_PASSWORD` | `moodlepass` | Database password |
| `DB_ROOT_PASSWORD` | `rootpass` | Database root password |
| `REDIS_HOST` | `redis` | Redis hostname |
| `S3_ENDPOINT` | `http://minio:9000` | S3/MinIO endpoint |
| `MOODLE_WWWROOT` | Auto | Site URL |

## Cloud Deployment

### Infrastructure as Code

The repository includes production-ready Terraform and Ansible configurations for AWS (extensible to GCP/Azure):

```
terraform/
  main.tf          # VPC, RDS, ElastiCache, ALB, Auto Scaling
  variables.tf     # Input variables with defaults
  outputs.tf       # Infrastructure outputs

ansible/
  playbook.yml           # Main playbook
  roles/
    appserver/           # EC2 app server configuration
    database/            # MySQL 8.4 server hardening
    loadbalancer/        # Nginx LB + SSL (Certbot)

scripts/
  auto-scale.sh          # Health-based auto-scaling
  failover-db.sh         # Database failover automation
  health-check.sh        # HTTP health probe

monitoring/
  prometheus.yml         # Prometheus scrape config
  alert-rules.yml        # AlertManager rules

.github/workflows/
  deploy.yml             # CI/CD pipeline (lint, test, deploy)
```

### Terraform Provisioning

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

### Ansible Configuration

```bash
# Create inventory
cat > ansible/inventory/hosts.ini << 'EOF'
[appservers]
app01 ansible_host=<public-ip>

[databases]
db01 ansible_host=<private-ip>

[loadbalancers]
lb01 ansible_host=<public-ip>
EOF

# Run playbook
cd ansible
ansible-playbook -i inventory/hosts.ini playbook.yml
```

### What Cloud Mode Provisions

- **VPC** with public/private subnets across 3 AZs
- **RDS MySQL 8.4** with Multi-AZ, automated backups, encryption
- **ElastiCache Redis 7.1** cluster with replication
- **Application Auto Scaling** with launch templates
- **ALB** with HTTP→HTTPS redirect and ACM certificate
- **S3 bucket** for moodledata with SSE
- **Security Groups** hardened for app, DB, and LB tiers

## Nginx Configuration

The `docker/nginx/default.conf.template` provides:

- Root set to `/var/www/html/moodle_app` (Moodle web root containing `index.php`)
- Static file caching with 30-day expiry
- PHP-FPM proxy via Docker DNS resolver
- Security headers (deny hidden files, vendor, node_modules)
- Client body size limit: 100M

## PHP-FPM Configuration

The `docker/php/www.conf` configures:

```ini
listen = 0.0.0.0:9000
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

PHP-FPM runs in foreground (`php-fpm -F`) as required.

## Moodle Configuration

`config.php.docker` is generated automatically from environment variables:

- MySQL 8.4 database connection
- Redis session handler (`\core\session\redis`)
- Optional S3/MinIO file storage via `tool_objectfs`
- Reverse proxy / SSL proxy settings via env vars

## Monitoring

### Prometheus Stack

```bash
cd monitoring
# Add prometheus container to docker-compose.yml or deploy separately
docker run -d -p 9090:9090 \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus
```

### Key Metrics

- Moodle HTTP response time and status
- MySQL connection pool and query performance
- Redis hit rate and memory usage
- Nginx request rate and latency
- PHP-FPM process metrics
- Node exporter for system metrics

### Alerts

- Moodle site down (critical)
- 95th percentile latency > 1s (warning)
- MySQL/Redis unreachable (critical)
- CPU > 85% or Memory > 90% (warning)
- Disk space < 10% (warning)

## CI/CD

GitHub Actions workflow (`.github/workflows/deploy.yml`):

1. **Lint** — Hadolint for Dockerfiles
2. **Build** — Multi-stage Docker build with layer caching
3. **Test** — Spin up stack, wait for DB health, run health checks
4. **Deploy Staging** — Auto-deploy on push to main
5. **Deploy Production** — Manual approval required

## Plugins

The `moodle-config.json` (or `config.json`) defines the Moodle branch and plugins:

```json
{
  "moodle_branch": "MOODLE_501_STABLE",
  "plugins": []
}
```

Add plugins with:

```json
{
  "name": "Plugin Name",
  "repository": "https://github.com/author/plugin.git",
  "version": "main",
  "destination": "mod/pluginname"
}
```

See `PLUGINS.md` for available plugins.

## Migration

See `MIGRATION.md` for migrating existing Moodle instances.

## Backup and Restore

```bash
# Database backup
docker compose exec mysql mysqldump -u root -p rootpass moodle > moodle_backup.sql

# Moodledata backup
tar -czf moodledata_backup.tar.gz moodledata/

# Restore
docker compose exec mysql mysql -u root -p rootpass moodle < moodle_backup.sql
tar -xzf moodledata_backup.tar.gz
```

## Troubleshooting

### Port Already in Use

The installer auto-selects a free port. Manually set `MOODLE_PORT` in `.env`.

### MySQL Connection Refused

Wait for health check. The installer waits up to 5 minutes.

### No CSS / Redirect Loops

Ensure `MOODLE_WWWROOT` matches your access URL. The config is automatically appended with `$CFG->reverseproxy = false; $CFG->sslproxy = false;` for local deployments.

## License

MIT

## Support

Issues: https://github.com/tuyijmv/REB-ELEARNING-OPTIMISATION/issues
