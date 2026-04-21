#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# install.sh - BeforeInstall Hook
# Installs Docker, AWS CLI, and other prerequisites
# Only installs if not already present
# ═══════════════════════════════════════════════════════════════

set -e

APP_NAME="github-aws-pipeline-app"
LOG_FILE="/var/log/codedeploy-${APP_NAME}.log"
APP_DIR="/opt/app"

# Function to log with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "════════════════════════════════════════"
log "  INSTALL PHASE STARTED"
log "════════════════════════════════════════"

# ─── Create Application Directory ───────────────────────────────
log "Creating application directory..."
mkdir -p $APP_DIR
mkdir -p /var/log/app

# ─── Install Docker (if not present) ────────────────────────────
if ! command -v docker &>/dev/null; then
  log "Docker not found. Installing Docker..."
  
  # Amazon Linux 2
  if [ -f /etc/os-release ] && grep -q "Amazon Linux" /etc/os-release; then
    yum update -y
    yum install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    log "Docker installed on Amazon Linux 2."
  
  # Ubuntu / Debian
  elif command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    log "Docker installed on Ubuntu."
  else
    log "ERROR: Unsupported OS. Install Docker manually."
    exit 1
  fi
else
  log "Docker already installed: $(docker --version)"
fi

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
  log "Starting Docker service..."
  systemctl start docker
fi

# ─── Install AWS CLI (if not present) ───────────────────────────
if ! command -v aws &>/dev/null; then
  log "AWS CLI not found. Installing..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  cd /tmp && unzip -q awscliv2.zip
  ./aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws
  log "AWS CLI installed: $(aws --version)"
else
  log "AWS CLI already installed: $(aws --version)"
fi

# ─── Pull latest ECR image ───────────────────────────────────────
log "Logging into Amazon ECR..."

# Get metadata from deployment manifest if it exists
if [ -f "$APP_DIR/deployment-manifest.json" ]; then
  ECR_REGISTRY=$(cat $APP_DIR/deployment-manifest.json | python3 -c "import sys, json; print(json.load(sys.stdin)['ecrRegistry'])" 2>/dev/null || echo "")
  IMAGE_URI=$(cat $APP_DIR/deployment-manifest.json | python3 -c "import sys, json; print(json.load(sys.stdin)['imageUri'])" 2>/dev/null || echo "")
  AWS_DEFAULT_REGION=$(cat $APP_DIR/deployment-manifest.json | python3 -c "import sys, json; print(json.load(sys.stdin)['region'])" 2>/dev/null || echo "${AWS_DEFAULT_REGION:-us-east-1}")
fi

# Use environment variables as fallback
ECR_REGISTRY=${ECR_REGISTRY:-"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-"us-east-1"}

if [ -n "$ECR_REGISTRY" ]; then
  aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY} && \
    log "ECR login successful." || \
    log "WARNING: ECR login failed. Will try with cached image."
fi

log "INSTALL PHASE COMPLETE"
exit 0
