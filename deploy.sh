#!/bin/bash
set -e

# ===========================================
# 🚀 Automated Docker Deployment Script
# For a Static HTML App from GitHub
# ===========================================

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOG_FILE") 2>&1
echo "🧰 Starting automated deployment..."

# -------------------------------------------
# Step 1: Collect User Inputs
# -------------------------------------------
read -p "Enter Git repository URL: " REPO_URL
read -p "Enter your Personal Access Token (PAT): " PAT
read -p "Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter remote server username: " SSH_USER
read -p "Enter server IP address: " SERVER_IP
read -p "Enter SSH key path: " SSH_KEY
read -p "Enter app internal container port: " APP_PORT

echo "✅ Inputs collected successfully!"

# -------------------------------------------
# Step 2: Clone or Update Repository
# -------------------------------------------
REPO_NAME=$(basename "$REPO_URL" .git)
if [ -d "$REPO_NAME" ]; then
  cd "$REPO_NAME"
  echo "📦 Repository exists, pulling latest changes..."
  git pull origin "$BRANCH"
else
  echo "📥 Cloning repository..."
  git clone -b "$BRANCH" "https://${PAT}@${REPO_URL#https://}" "$REPO_NAME"
  cd "$REPO_NAME"
fi

# -------------------------------------------
# Step 3: Check for Dockerfile
# -------------------------------------------
if [ ! -f "Dockerfile" ]; then
  echo "⚠️ No Dockerfile found. Creating one for static HTML app..."
  cat > Dockerfile <<'DOCKERFILE'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
DOCKERFILE
  echo "✅ Dockerfile created."
else
  echo "✅ Dockerfile found."
fi

# -------------------------------------------
# Step 4: Test SSH Connection
# -------------------------------------------
echo "🌐 Testing SSH connectivity..."
if ! ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" "echo connected" >/dev/null 2>&1; then
  echo "❌ SSH connection failed! Check credentials, IP, or key."
  exit 2
fi
echo "✅ SSH connectivity verified."

# -------------------------------------------
# Step 5: Prepare Remote Environment
# -------------------------------------------
echo "⚙️ Preparing remote server environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash -s <<'EOF_REMOTE'
set -e
echo "🧩 Updating system packages..."
if [ -x "$(command -v apt)" ]; then
  sudo apt update -y && sudo apt upgrade -y
  PKG_MGR="apt"
elif [ -x "$(command -v yum)" ]; then
  sudo yum update -y
  PKG_MGR="yum"
else
  echo "Unsupported package manager."
  exit 3
fi

echo "🐳 Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  if [ "$PKG_MGR" = "apt" ]; then
    sudo apt install -y docker.io
  else
    sudo yum install -y docker
  fi
fi

echo "🔧 Installing Docker Compose..."
if ! command -v docker-compose >/dev/null 2>&1; then
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $(whoami) || true

echo "🌍 Installing NGINX..."
if [ "$PKG_MGR" = "apt" ]; then
  sudo apt install -y nginx
else
  sudo yum install -y nginx
fi
sudo systemctl enable nginx
sudo systemctl start nginx

echo "✅ Remote environment ready."
EOF_REMOTE

# -------------------------------------------
# Step 6: Cleanup Old Files & Prepare Directory
# -------------------------------------------
echo "🧹 Cleaning remote environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash -s <<'EOF_CLEAN'
set -e
USER_NAME=$(whoami)

sudo docker ps -aq | xargs -r sudo docker rm -f || true
sudo docker system prune -af || true

sudo rm -rf ~/app
sudo mkdir -p ~/app
sudo chown "$USER_NAME":"$USER_NAME" ~/app
EOF_CLEAN

# -------------------------------------------
# Step 7: Transfer Project Files
# -------------------------------------------
echo "📦 Transferring files to remote server..."
scp -i "$SSH_KEY" -r ./* "$SSH_USER@$SERVER_IP:~/app"

# -------------------------------------------
# Step 8: Deploy Dockerized Application
# -------------------------------------------
echo "🐳 Deploying application with Docker..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash -s <<EOF_DEPLOY
set -e
cd ~/app
APP_NAME=\$(basename \$(pwd))

sudo docker stop \$APP_NAME || true
sudo docker rm \$APP_NAME || true
sudo docker build -t \$APP_NAME .
sudo docker run -d -p $APP_PORT:80 --name \$APP_NAME \$APP_NAME

echo "✅ Docker container deployed successfully."
EOF_DEPLOY

# -------------------------------------------
# Step 9: Configure NGINX Reverse Proxy
# -------------------------------------------
echo "🌐 Configuring NGINX reverse proxy..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" sudo bash -s <<EOF_NGINX
set -e
NGINX_CONF="/etc/nginx/conf.d/app.conf"

cat > \$NGINX_CONF <<NGINXCONF
server {
    listen 80;
    server_name $SERVER_IP;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

sudo nginx -t && sudo systemctl reload nginx
echo "✅ NGINX configured successfully."
EOF_NGINX

# -------------------------------------------
# Step 10: Validate Deployment
# -------------------------------------------
echo "🧪 Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -I http://localhost || true"

echo "✅ Deployment complete! Visit: http://$SERVER_IP"
