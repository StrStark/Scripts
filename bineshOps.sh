#!/bin/bash
set -e

echo "========== Binesh Deployment Script Started =========="

### VARIABLES
BASE_DIR="/Binesh"
DOMAIN="panel.bineshafzar.ir"
EMAIL="rezafathisamani1383@gmail.com"
NGINX_SITE="Binesh"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

FRONT_PORT=801
BACK_PORT=800

# Postgres
DB_PASSWORD="Mr5568###"

# MongoDB — change these before deploying, never commit real passwords
MONGO_USER="binesh_admin"
MONGO_PASSWORD="Mn7!xQ#2kLp9"
MONGO_DB="binesh_chat"

# OpenAI — set this as a server environment variable, never hardcode here
# export OPENAI_API_KEY="sk-proj-..."  ← run this on the server before deploying
OPENAI_API_KEY="${OPENAI_API_KEY:?ERROR: OPENAI_API_KEY environment variable is not set. Run: export OPENAI_API_KEY=your-key}"
OPENAI_MODEL="gpt-4o"

FRONT_REPO="https://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@github.com/StrStark/BineshFront.git"
BACK_REPO="https://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@github.com/StrStark/BineshSolution.git"

BACK_DOCKERFILE_DIR="./BineshSolution/src/DataBaseManager/"
FRONT_DOCKERFILE_DIR="./BineshFront"

### 0. Ensure base directories exist
echo ">>> Ensuring base directory exists and is empty: $BASE_DIR"
rm -rf $BASE_DIR
mkdir -p "$BASE_DIR"

### 1. Pull GitHub projects
echo ">>> Cloning GitHub repositories"
cd $BASE_DIR
git clone "$FRONT_REPO"
git clone "$BACK_REPO"
cd "/"
echo ">>> Repositories cloned"

### 2. Ensure volumes exist with correct permissions
echo ">>> Ensuring data volumes exist"
mkdir -p /DataBase
chown -R 999:999 /DataBase
chmod 700 /DataBase

mkdir -p /MongoData
# MongoDB runs as uid 999 inside the official image
chown -R 999:999 /MongoData
chmod 700 /MongoData

### 3. Generate docker-compose.yml
echo ">>> Generating docker-compose.yml"
cat > "$COMPOSE_FILE" <<EOF
services:

  BineshBack:
    build:
      context: $BACK_DOCKERFILE_DIR
      dockerfile: Dockerfile
    image: binesh-back:latest
    ports:
      - "$BACK_PORT:8000"
    environment:
      CONN_STRING: "Host=BineshDb;Port=5432;Database=BineshDb;Username=StrStark;Password=$DB_PASSWORD"
      MONGODB__CONNECTIONSTRING: "mongodb://${MONGO_USER}:${MONGO_PASSWORD}@BineshMongo:27017"
      MONGODB__DATABASENAME: "$MONGO_DB"
      OPENAI__APIKEY: "$OPENAI_API_KEY"
      OPENAI__MODEL: "$OPENAI_MODEL"
    depends_on:
      - BineshDb
      - BineshMongo

  BineshFront:
    build:
      context: $FRONT_DOCKERFILE_DIR
      dockerfile: Dockerfile
    image: binesh-front:latest
    ports:
      - "$FRONT_PORT:80"
    depends_on:
      - BineshBack

  BineshDb:
    image: postgres:latest
    container_name: BineshDb
    restart: always
    environment:
      POSTGRES_DB: BineshDb
      POSTGRES_USER: StrStark
      POSTGRES_PASSWORD: $DB_PASSWORD
    volumes:
      - /DataBase:/var/lib/postgresql

  BineshMongo:
    image: mongo:7
    container_name: BineshMongo
    restart: always
    environment:
      MONGO_INITDB_ROOT_USERNAME: $MONGO_USER
      MONGO_INITDB_ROOT_PASSWORD: $MONGO_PASSWORD
      MONGO_INITDB_DATABASE: $MONGO_DB
    volumes:
      - /MongoData:/data/db

EOF

echo ">>> docker-compose.yml created"

### 4. Start Docker Compose stack
echo ">>> Building and starting Docker Compose stack"
docker compose -f "$COMPOSE_FILE" up -d --build
echo ">>> Stack starting..."

### 5. Wait for all containers
echo ">>> Waiting for all containers to be running"
while true; do
    running=$(docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
    total=$(docker compose -f "$COMPOSE_FILE" ps --services | wc -l)
    if [ "$running" -eq "$total" ]; then
        break
    fi
    echo ">>> Waiting... ($running/$total running)"
    sleep 5
done
echo ">>> All containers are running"

### 6. Create Nginx config
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

    # Backend API + WebSocket support
    location /api/ {
        proxy_pass http://127.0.0.1:$BACK_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # Prevent Nginx from closing idle WebSocket connections
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Swagger
    location /swagger/ {
        proxy_pass http://127.0.0.1:$BACK_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

echo ">>> Nginx config created"

### 7. Enable Nginx site
echo ">>> Enabling Nginx site"
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/$NGINX_SITE
nginx -t
systemctl reload nginx
echo ">>> Nginx reloaded"

### 8. TLS certificate
echo ">>> Requesting TLS certificate"
certbot --nginx \
  -d $DOMAIN \
  --email $EMAIL \
  --agree-tos \
  --non-interactive \
  --redirect
echo ">>> TLS certificate installed"

### 9. Final status
echo "========== Binesh Deployment Completed =========="
echo "Domain  : https://$DOMAIN"
echo "Frontend: https://$DOMAIN/"
echo "API     : https://$DOMAIN/api"
echo "Swagger : https://$DOMAIN/swagger/index.html"
