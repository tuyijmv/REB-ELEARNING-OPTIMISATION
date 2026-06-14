# Nginx for Moodle
FROM nginx:alpine

# Copy custom Nginx configuration template
COPY default.conf.template /etc/nginx/conf.d/default.conf.template

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Create directory for logs
RUN mkdir -p /var/log/nginx

# Set default environment variables (can be overridden)
ENV PHP_FPM_HOST=php
ENV NGINX_PORT=8080

# Expose HTTP port (documentation only - actual port is set via NGINX_PORT env var)
EXPOSE ${NGINX_PORT}

# Health check using the NGINX_PORT environment variable
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD sh -c 'wget --quiet --tries=1 --spider http://localhost:${NGINX_PORT}/ || exit 1'

# Use custom entrypoint to substitute env vars
ENTRYPOINT ["/docker-entrypoint.sh"]
