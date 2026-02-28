#!/bin/bash

# ============================================================
#   🚀 Rocket.Chat Production Deployment Script
#   Stack: Docker + Nginx + Certbot (Let's Encrypt)
# ============================================================

set -e  # Exit immediately on any error

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Helpers ─────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[✔]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[✘ ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ─── Pre-flight: must run as root ────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root or with sudo:\n  sudo bash $0"
fi

# ============================================================
#   CONFIGURATION — Edit these values before running
# ============================================================

RC_DOMAIN="chat.bineshafzar.ir"
GRAFANA_DOMAIN="graf.bineshafzar.ir"
LETSENCRYPT_EMAIL="rezafathisamani1383@gmail.com"
RELEASE="8.1.1"
MONGODB_VERSION="7.0"
GRAFANA_ADMIN_PASSWORD="Mr5568###"

INSTALL_DIR="/opt/rocketchat"

# ============================================================
#   STEP 0 — Pre-flight checks
# ============================================================
section "STEP 0 — Pre-flight Checks"

# Check required tools
for cmd in docker git nginx certbot; do
  if command -v "$cmd" &>/dev/null; then
    success "$cmd is installed"
  else
    error "$cmd is not installed. Please install it and re-run the script."
  fi
done

# Check docker compose v2
if docker compose version &>/dev/null; then
  success "Docker Compose v2 is available"
else
  error "Docker Compose v2 not found. Please install it and re-run."
fi

# Check ports 80 and 443 are free
for port in 80 443; do
  if ss -tlnp | grep -q ":${port} "; then
    warn "Port $port is currently in use. Nginx/Certbot may fail. Stopping nginx if running..."
    systemctl stop nginx 2>/dev/null || true
    break
  fi
done

success "Pre-flight checks passed!"

# ============================================================
#   STEP 1 — Clone Rocket.Chat Compose Repo
# ============================================================
section "STEP 1 — Clone Rocket.Chat Repository"

if [ -d "$INSTALL_DIR" ]; then
  warn "Directory $INSTALL_DIR already exists. Skipping clone."
else
  info "Cloning into $INSTALL_DIR ..."
  git clone --depth 1 https://github.com/RocketChat/rocketchat-compose.git "$INSTALL_DIR"
  success "Repository cloned to $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ============================================================
#   STEP 2 — Write the .env File
# ============================================================
section "STEP 2 — Writing .env Configuration"

cat > "$INSTALL_DIR/.env" <<EOF
# ── Rocket.Chat ──────────────────────────────────────
RELEASE=${RELEASE}

# Run on localhost — Nginx handles public HTTPS
DOMAIN=localhost
ROOT_URL=http://localhost

# Traefik disabled — Nginx used instead
LETSENCRYPT_ENABLED=false
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
TRAEFIK_PROTOCOL=http

# ── Grafana ──────────────────────────────────────────
# Subdomain mode: domain set here, path left empty
GRAFANA_DOMAIN=
GRAFANA_PATH=
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# ── MongoDB ──────────────────────────────────────────
MONGODB_VERSION=${MONGODB_VERSION}
EOF

success ".env file written successfully"

# ============================================================
#   STEP 3 — Launch Docker Services (without Traefik)
# ============================================================
section "STEP 3 — Launching Docker Containers"

info "Pulling images and starting containers..."
docker compose -f compose.database.yml -f compose.monitoring.yml -f compose.yml up -d

info "Waiting 15 seconds for containers to initialize..."
sleep 15

info "Running container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

success "Docker containers are up!"

# ============================================================
#   STEP 4 — Obtain SSL Certificates with Certbot
# ============================================================
section "STEP 4 — Obtaining SSL Certificates"

info "Stopping Nginx to free port 80 for Certbot standalone mode..."
systemctl stop nginx 2>/dev/null || true
sleep 2

info "Requesting certificates for: $RC_DOMAIN and $GRAFANA_DOMAIN"
certbot certonly --standalone \
  --non-interactive \
  --agree-tos \
  --email "$LETSENCRYPT_EMAIL" \
  -d "$RC_DOMAIN" \
  -d "$GRAFANA_DOMAIN"

success "SSL certificates obtained!"
info "  Rocket.Chat cert: /etc/letsencrypt/live/${RC_DOMAIN}/fullchain.pem"
info "  Grafana cert:     /etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem"

# ============================================================
#   STEP 5 — Configure Nginx Virtual Hosts
# ============================================================
section "STEP 5 — Configuring Nginx"

# ── Backup default config ──
if [ -f /etc/nginx/sites-available/default ]; then
  mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.reference
  info "Backed up default Nginx config to default.reference"
fi

# ── Rocket.Chat vhost ──
info "Writing Nginx config for $RC_DOMAIN ..."
cat > /etc/nginx/sites-available/rocketchat <<EOF
# ─── Redirect HTTP → HTTPS ──────────────────────────────────
server {
    listen 80;
    server_name ${RC_DOMAIN};
    return 301 https://\$host\$request_uri;
}

# ─── Rocket.Chat HTTPS ──────────────────────────────────────
server {
    listen 443 ssl;
    server_name ${RC_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${RC_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${RC_DOMAIN}/privkey.pem;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers         'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    location / {
        proxy_pass         http://localhost:3000/;
        proxy_http_version 1.1;

        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       \$http_host;

        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Nginx-Proxy     true;

        proxy_redirect off;

        # Generous timeouts for WebSocket / long-polling
        proxy_read_timeout  900;
        proxy_send_timeout  900;
    }
}
EOF

# ── Grafana vhost ──
info "Writing Nginx config for $GRAFANA_DOMAIN ..."
cat > /etc/nginx/sites-available/grafana <<EOF
# ─── Redirect HTTP → HTTPS ──────────────────────────────────
server {
    listen 80;
    server_name ${GRAFANA_DOMAIN};
    return 301 https://\$host\$request_uri;
}

# ─── Grafana HTTPS ──────────────────────────────────────────
server {
    listen 443 ssl;
    server_name ${GRAFANA_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${GRAFANA_DOMAIN}/privkey.pem;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers         'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass         http://localhost:5050/;
        proxy_http_version 1.1;

        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       \$http_host;

        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Nginx-Proxy     true;

        proxy_redirect off;
    }
}
EOF

# ── Enable sites ──
ln -sf /etc/nginx/sites-available/rocketchat /etc/nginx/sites-enabled/rocketchat
ln -sf /etc/nginx/sites-available/grafana    /etc/nginx/sites-enabled/grafana

# ── Remove default symlink if it exists ──
rm -f /etc/nginx/sites-enabled/default

# ── Test config ──
info "Testing Nginx configuration..."
if nginx -t; then
  success "Nginx config is valid!"
else
  error "Nginx config has errors. Check the output above."
fi

# ============================================================
#   STEP 6 — Start & Enable Nginx
# ============================================================
section "STEP 6 — Starting Nginx"

systemctl start nginx
systemctl enable nginx
success "Nginx started and enabled on boot"

# ============================================================
#   STEP 7 — Set Up Automatic Certificate Renewal
# ============================================================
section "STEP 7 — Auto-Renewal Cron Job"

CRON_JOB="0 3 * * * certbot renew --quiet --pre-hook \"systemctl stop nginx\" --post-hook \"systemctl start nginx\""

# Add only if not already present
if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  success "Auto-renewal cron job added (runs daily at 3 AM)"
else
  warn "Certbot renewal cron job already exists. Skipping."
fi

# ============================================================
#   DONE — Summary
# ============================================================
section "🎉 Deployment Complete!"

echo -e "${BOLD}Your services are live:${NC}\n"
echo -e "  🚀 Rocket.Chat  →  ${GREEN}https://${RC_DOMAIN}${NC}"
echo -e "  📊 Grafana      →  ${GREEN}https://${GRAFANA_DOMAIN}${NC}  (admin / ${GRAFANA_ADMIN_PASSWORD})"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Visit https://${RC_DOMAIN} and complete the setup wizard"
echo -e "  2. Change your Grafana password in the UI after first login"
echo -e "  3. Close ports 3000 and 5050 in your firewall — Nginx handles all traffic"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  Live logs:    docker compose logs -f rocketchat"
echo -e "  All logs:     docker compose logs -f"
echo -e "  Restart RC:   docker compose restart rocketchat"
echo -e "  Nginx log:    sudo tail -f /var/log/nginx/error.log"
echo -e "  Backup DB:    docker exec rocketchat-mongodb-1 sh -c 'mongodump --archive' > ~/backup_\$(date +%Y%m%d).dump"
echo ""