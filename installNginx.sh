#!/bin/bash
set -e

echo "========== Installing Nginx + Certbot =========="

# 1. Update system
echo "[1/7] Updating system..."
sudo apt-get update -y

# 2. Clean old Nginx installs (safe if none exist)
echo "[2/7] Cleaning old Nginx installations..."
sudo apt-get remove -y nginx nginx-common nginx-core || true
sudo apt-get autoremove -y

# 3. Install Nginx
echo "[3/7] Installing Nginx..."
sudo apt-get install -y nginx

# 4. Install Certbot + Nginx plugin
echo "[4/7] Installing Certbot..."
sudo apt-get install -y certbot python3-certbot-nginx

# 5. Enable and start Nginx
echo "[5/7] Enabling and starting Nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx

# 6. Configure firewall (if UFW exists)
if command -v ufw >/dev/null 2>&1; then
    echo "[6/7] Configuring firewall..."
    sudo ufw allow OpenSSH || true
    sudo ufw allow 'Nginx Full' || true
fi

# 7. Enable Certbot auto-renewal
echo "[7/7] Enabling Certbot auto-renewal..."
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
sudo certbot renew --dry-run

# Verification
echo "========== Verification =========="
nginx -v
certbot --version
systemctl list-timers | grep certbot || true
