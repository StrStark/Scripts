#!/bin/bash
set -e

echo "========== Docker Registry Deployment Started =========="

### VARIABLES
BASE_DIR="/DockerRegistry"
DOMAIN="DockerReg.bineshafzar.ir"
EMAIL="rezafathisamani1383@gmail.com"
NGINX_SITE="DockerRegistry"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

REGISTRY_PORT=798

### 0. Prepare directory
echo ">>> Preparing base directory $BASE_DIR"
rm -rf $BASE_DIR
mkdir -p $BASE_DIR/data
mkdir -p $BASE_DIR/auth
cd $BASE_DIR

### 1. Create docker-compose.yml
echo ">>> Generating docker-compose.yml"

cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  registry:
    image: registry:2
    container_name: docker-registry
    restart: always
    ports:
      - "$REGISTRY_PORT:5000"
    environment:
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
    volumes:
      - $BASE_DIR/data:/var/lib/registry
EOF

echo ">>> docker-compose.yml created"

### 2. Start registry
echo ">>> Starting Docker Registry"
docker compose -f "$COMPOSE_FILE" up -d

echo ">>> Registry container started"

### 3. Create NGINX Config
echo ">>> Creating NGINX configuration"

cat > /etc/nginx/sites-available/$NGINX_SITE <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 5G;

    location / {
        proxy_pass http://127.0.0.1:$REGISTRY_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 900;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/$NGINX_SITE

nginx -t
systemctl reload nginx

echo ">>> NGINX configured"

### 4. Get TLS Certificate
echo ">>> Requesting TLS certificate"
certbot --nginx \
  -d $DOMAIN \
  --email $EMAIL \
  --agree-tos \
  --non-interactive \
  --redirect

echo "========== Docker Registry Deployment Completed =========="
echo "Registry URL: https://$DOMAIN"
