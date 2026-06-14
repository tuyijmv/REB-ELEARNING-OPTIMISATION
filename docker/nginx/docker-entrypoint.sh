#!/bin/sh
set -e

# Set defaults if not provided
export PHP_FPM_HOST=${PHP_FPM_HOST:-php}
export NGINX_PORT=${NGINX_PORT:-8080}

echo "Configuring Nginx:"
echo "  - Listen port: ${NGINX_PORT}"
echo "  - PHP-FPM upstream: ${PHP_FPM_HOST}:9000"

# Substitute environment variables in the template
envsubst '${PHP_FPM_HOST} ${NGINX_PORT}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

echo "Nginx configuration ready. Starting Nginx..."

# Start nginx
exec nginx -g 'daemon off;'
