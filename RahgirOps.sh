#!/bin/bash
set -e

echo "========== Rahgir Deployment Script Started =========="

### VARIABLES
BASE_DIR="/Rahgir"
DOMAIN="rahgir.bineshafzar.ir"
EMAIL="rezafathisamani1383@gmail.com"
NGINX_SITE="Rahgir"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

FRONT_PORT=802
BACK_PORT=800

# Updated safe password
DB_PASSWORD="Mr5568###"

FRONT_REPO="https://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@github.com/StrStark/Rahgirfigma.git"
# BACK_REPO="https://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@github.com/StrStark/BineshSolution.git"

# BACK_DOKCERFILE_DIR="./BineshSolution/src/DataBaseManager/"
FRONT_DOCKERFILE_DIR="./Rahgirfigma"

### 0. Ensure base directories exist
echo ">>> Ensuring base directory exists and its Empty: $BASE_DIR"
rm -rf $BASE_DIR
mkdir -p "$BASE_DIR"

### 1. Pull GitHub projects
echo ">>> Cloning or updating GitHub repositories"

cd $BASE_DIR 

git clone "$FRONT_REPO"
# git clone "$BACK_REPO"

cd "/"

echo ">>> GitHub repositories are up to date"

### 2. Generate docker-compose.yml
echo ">>> Generating docker-compose.yml in $BASE_DIR"

# cat > "$COMPOSE_FILE" <<EOF
# services:
#   BineshBack:
#     build:
#       context: $BACK_DOKCERFILE_DIR
#       dockerfile: Dockerfile
#     image: binesh-back:latest
#     ports:
#       - "$BACK_PORT:8000"
#     environment:
#       CONN_STRING: "Host=BineshDb;Port=5432;Database=BineshDb;Username=StrStark;Password=$DB_PASSWORD"
#     depends_on:
#       - BineshDb

#   BineshFront:
#     build:
#       context: $FRONT_DOCKERFILE_DIR
#       dockerfile: Dockerfile
#     image: binesh-front:latest
#     ports:
#       - "$FRONT_PORT:80"
#     depends_on:
#       - BineshBack

#   BineshDb:
#     image: postgres:latest
#     container_name: BineshDb
#     restart: always
#     environment:
#       POSTGRES_DB: BineshDb
#       POSTGRES_USER: StrStark
#       POSTGRES_PASSWORD: $DB_PASSWORD
#     volumes:
#       - /DataBase:/var/lib/postgresql   # Compatible with Postgres 18+
# EOF

cat > "$COMPOSE_FILE" <<EOF
services:
  BineshFront:
    build:
      context: $FRONT_DOCKERFILE_DIR
      dockerfile: Dockerfile
    image: binesh-front:latest
    ports:
      - "$FRONT_PORT:80"

EOF

echo ">>> docker-compose.yml created successfully"

### 3. Ensure Postgres volume exists
# echo ">>> Ensuring Postgres volume /DataBase exists and has correct permissions"
# mkdir -p /DataBase
# chown -R 999:999 /DataBase
# chmod 700 /DataBase

### 4. Start Docker Compose stack
echo ">>> Building and starting Docker Compose stack"
docker compose -f "$COMPOSE_FILE" up -d --build

echo ">>> Docker Compose stack is starting..."

# Wait until all containers are running
echo ">>> Waiting for all containers to be running"
while true; do
    running=$(docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
    total=$(docker compose -f "$COMPOSE_FILE" ps --services | wc -l)
    if [ "$running" -eq "$total" ]; then
        break
    fi
    echo ">>> Waiting for containers... ($running/$total running)"
    sleep 5
done

echo ">>> All containers are running"

### 5. Create Nginx config
echo ">>> Creating Nginx site configuration"
cat > /etc/nginx/sites-available/$NGINX_SITE <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Frontend
    location / {
        proxy_pass http://127.0.0.1:$FRONT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Backend API
    # location /api/ {
    #     proxy_pass http://127.0.0.1:$BACK_PORT;
    #     proxy_http_version 1.1;
    #     proxy_set_header Upgrade \$http_upgrade;
    #     proxy_set_header Connection "upgrade";
    #     proxy_set_header Host \$host;
    #     proxy_set_header X-Real-IP \$remote_addr;
    #     proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    #     proxy_set_header X-Forwarded-Proto \$scheme;
    # }

    # Swagger
    # location /swagger/ {
    #     proxy_pass http://127.0.0.1:$BACK_PORT;
    #     proxy_http_version 1.1;
    #     proxy_set_header Upgrade \$http_upgrade;
    #     proxy_set_header Connection "upgrade";
    #     proxy_set_header Host \$host;
    # }
}
EOF

echo ">>> Nginx config created at /etc/nginx/sites-available/$NGINX_SITE"

### 6. Enable Nginx site
echo ">>> Enabling Nginx site"
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/$NGINX_SITE
nginx -t
systemctl reload nginx
echo ">>> Nginx site enabled and reloaded"

### 7. Obtain TLS certificate with Certbot
echo ">>> Requesting TLS certificate from Let's Encrypt"
certbot --nginx \
  -d $DOMAIN \
  --email $EMAIL \
  --agree-tos \
  --non-interactive \
  --redirect

echo ">>> TLS certificate installed successfully"

### 8. Final Status
echo "========== Binesh Deployment Completed =========="
echo "Domain: https://$DOMAIN"
echo "Frontend: https://$DOMAIN/"
# echo "Backend API: https://$DOMAIN/api"
# echo "Swagger: https://$DOMAIN/swagger/index.html"