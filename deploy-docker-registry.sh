#!/bin/bash
set -e

echo "========== Docker Registry Deployment Started =========="

### VARIABLES
BASE_DIR="/DockerRegistry"
DOMAIN="DockerReg.bineshafzar.ir"
EMAIL="rezafathisamani1383@gmail.com"
NGINX_SITE="DockerRegistry"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

REGISTRY_PORT=5000
AUTH_USER="StrStark"
AUTH_PASSWORD="Mr5568###"   # CHANGE THIS

### 0. Prepare directories
echo ">>> Preparing base directory"
rm -rf $BASE_DIR
mkdir -p $BASE_DIR/data
mkdir -p $BASE_DIR/auth

### 1. Install htpasswd tool if missing
if ! command -v htpasswd &> /dev/null
then
    echo ">>> Installing apache2-utils"
    apt update
    apt install -y apache2-utils
fi

### 2. Create htpasswd file
echo ">>> Creating authentication file"
htpasswd -bc $BASE_DIR/auth/htpasswd $AUTH_USER $AUTH_PASSWORD

### 3. Generate docker-compose.yml
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
    volumes:
      - $BASE_DIR/data:/var/lib/registry
EOF

### 4. Start registry
echo ">>> Starting Docker Registry"
docker compose -f "$COMPOSE_FILE" up -d

### 5. Create NGINX config with Auth
echo ">>> Creating NGINX configuration"

cat > /etc/nginx/sites-available/$NGINX_SITE <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 5G;

    auth_basic "Private Docker Registry";
    auth_basic_user_file $BASE_DIR/auth/htpasswd;

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

### 6. Enable NGINX site
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/$NGINX_SITE
nginx -t
systemctl reload nginx

### 7. Obtain TLS certificate
echo ">>> Requesting TLS certificate"
certbot --nginx \
  -d $DOMAIN \
  --email $EMAIL \
  --agree-tos \
  --non-interactive \
  --redirect

echo "========== Deployment Completed =========="
echo "Registry URL: https://$DOMAIN"
echo "Username: $AUTH_USER"
