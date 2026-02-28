#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "=== Starting Docker installation ==="

# 1. Update system packages
echo "Updating system packages..."
sudo apt-get update -y

# 2. Remove old versions of Docker
echo "Removing old Docker versions if any..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

# 3. Install required packages
echo "Installing prerequisite packages..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 4. Add Docker’s official GPG key
echo "Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 5. Set up the Docker repository
echo "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 6. Install Docker Engine
echo "Installing Docker Engine..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 7. Enable and start Docker service
echo "Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

# 8. Verify Docker installation
echo "Verifying Docker installation..."
docker --version
docker compose version

echo "=== Docker and Docker Compose installation completed successfully ==="