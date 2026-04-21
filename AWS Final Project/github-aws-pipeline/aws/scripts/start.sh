#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# start.sh - ApplicationStart Hook
# Pulls Docker image from ECR and starts the container
# ═══════════════════════════════════════════════════════════════

set -e

APP_NAME="github-aws-pipeline-app"
APP_DIR="/opt/app"
LOG_FILE="/var/log/codedeploy-${APP_NAME}.log"
ENV_FILE="${APP_DIR}/.env"
HOST_PORT=80
CONTAINER_PORT=3000
RESTART_POLICY="unless-stopped"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "════════════════════════════════════════"
log "  START PHASE STARTED"
log "════════════════════════════════════════"

# ─── Read Deployment Config ──────────────────────────────────────
if [ -f "${APP_DIR}/deployment-manifest.json" ]; then
  IMAGE_URI=$(python3 -c "import json; d=json.load(open('${APP_DIR}/deployment-manifest.json')); print(d.get('imageUri',''))" 2>/dev/null || echo "")
  IMAGE_TAG=$(python3 -c "import json; d=json.load(open('${APP_DIR}/deployment-manifest.json')); print(d.get('imageTag','latest'))" 2>/dev/null || echo "latest")
  ECR_REGISTRY=$(python3 -c "import json; d=json.load(open('${APP_DIR}/deployment-manifest.json')); print(d.get('ecrRegistry',''))" 2>/dev/null || echo "")
  AWS_REGION=$(python3 -c "import json; d=json.load(open('${APP_DIR}/deployment-manifest.json')); print(d.get('region','us-east-1'))" 2>/dev/null || echo "us-east-1")
fi

if [ -z "$IMAGE_URI" ]; then
  log "ERROR: IMAGE_URI not found in deployment manifest!"
  log "Contents of deployment-manifest.json:"
  cat ${APP_DIR}/deployment-manifest.json 2>/dev/null || echo "File not found"
  exit 1
fi

log "Image URI: $IMAGE_URI"
log "Image Tag: $IMAGE_TAG"

# ─── Re-authenticate to ECR ──────────────────────────────────────
log "Authenticating to ECR..."
aws ecr get-login-password --region ${AWS_REGION:-us-east-1} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY} && \
  log "ECR authentication successful." || {
    log "WARNING: ECR authentication failed. Trying to use cached image..."
  }

# ─── Pull Latest Image ───────────────────────────────────────────
log "Pulling Docker image from ECR: $IMAGE_URI"
docker pull $IMAGE_URI && log "Image pulled successfully." || {
  log "ERROR: Failed to pull image $IMAGE_URI"
  exit 1
}

# ─── Start Docker Container ──────────────────────────────────────
log "Starting Docker container..."

docker run \
  --detach \
  --name $APP_NAME \
  --restart $RESTART_POLICY \
  --publish ${HOST_PORT}:${CONTAINER_PORT} \
  --env-file $ENV_FILE \
  --env DEPLOYMENT_ID="${DEPLOYMENT_ID:-unknown}" \
  --env DEPLOY_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --log-driver awslogs \
  --log-opt awslogs-region=${AWS_REGION:-us-east-1} \
  --log-opt awslogs-group=/aws/ec2/${APP_NAME} \
  --log-opt awslogs-create-group=true \
  --log-opt awslogs-stream="${INSTANCE_ID:-$(hostname)}" \
  --memory 512m \
  --cpu-shares 512 \
  --health-cmd="curl -f http://localhost:${CONTAINER_PORT}/health || exit 1" \
  --health-interval=30s \
  --health-retries=3 \
  --health-start-period=30s \
  --health-timeout=10s \
  $IMAGE_URI

log "Container started. Waiting for it to be healthy..."

# ─── Wait for Health Check ───────────────────────────────────────
MAX_RETRIES=12
RETRY_INTERVAL=5
RETRIES=0

while [ $RETRIES -lt $MAX_RETRIES ]; do
  sleep $RETRY_INTERVAL
  
  CONTAINER_STATUS=$(docker inspect --format='{{.State.Health.Status}}' $APP_NAME 2>/dev/null || echo "unknown")
  CONTAINER_RUNNING=$(docker inspect --format='{{.State.Running}}' $APP_NAME 2>/dev/null || echo "false")
  
  log "Health status: $CONTAINER_STATUS | Running: $CONTAINER_RUNNING (attempt $((RETRIES+1))/$MAX_RETRIES)"
  
  if [ "$CONTAINER_STATUS" = "healthy" ]; then
    log "Container is healthy! ✅"
    break
  fi
  
  if [ "$CONTAINER_RUNNING" = "false" ]; then
    log "ERROR: Container stopped unexpectedly!"
    log "Container logs:"
    docker logs $APP_NAME --tail 50 2>&1 | tee -a $LOG_FILE
    exit 1
  fi
  
  RETRIES=$((RETRIES + 1))
done

if [ $RETRIES -eq $MAX_RETRIES ]; then
  log "WARNING: Container did not become healthy within timeout."
  log "Container logs:"
  docker logs $APP_NAME --tail 50 2>&1 | tee -a $LOG_FILE
fi

# ─── Verify Container is Running ─────────────────────────────────
CONTAINER_ID=$(docker ps -q --filter "name=${APP_NAME}" 2>/dev/null || echo "")
if [ -n "$CONTAINER_ID" ]; then
  log "Container is running with ID: $CONTAINER_ID"
  docker ps --filter "name=${APP_NAME}" | tee -a $LOG_FILE
else
  log "ERROR: Container is not running!"
  exit 1
fi

log "START PHASE COMPLETE ✅"
exit 0
