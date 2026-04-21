#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# validate.sh - ValidateService Hook
# Verifies the application is running correctly after deployment
# ═══════════════════════════════════════════════════════════════

set -e

APP_NAME="github-aws-pipeline-app"
LOG_FILE="/var/log/codedeploy-${APP_NAME}.log"
APP_PORT=80
MAX_RETRIES=10
RETRY_INTERVAL=5

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "════════════════════════════════════════"
log "  VALIDATE PHASE STARTED"
log "════════════════════════════════════════"

# ─── Check Container is Running ──────────────────────────────────
log "Checking if container is running..."
CONTAINER_ID=$(docker ps -q --filter "name=${APP_NAME}")

if [ -z "$CONTAINER_ID" ]; then
  log "ERROR: Container '${APP_NAME}' is not running!"
  log "Docker PS output:"
  docker ps -a | tee -a $LOG_FILE
  exit 1
fi

log "Container is running: $CONTAINER_ID ✅"

# ─── Health Check via HTTP ───────────────────────────────────────
log "Testing HTTP health endpoint..."
RETRIES=0
SUCCESS=false

while [ $RETRIES -lt $MAX_RETRIES ]; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    --max-time 10 \
    http://localhost:${APP_PORT}/health 2>/dev/null || echo "000")
  
  log "HTTP health check attempt $((RETRIES+1))/$MAX_RETRIES: Status $HTTP_STATUS"
  
  if [ "$HTTP_STATUS" = "200" ]; then
    SUCCESS=true
    log "Health check passed! Status: $HTTP_STATUS ✅"
    break
  fi
  
  RETRIES=$((RETRIES + 1))
  sleep $RETRY_INTERVAL
done

if [ "$SUCCESS" != "true" ]; then
  log "ERROR: Health check failed after $MAX_RETRIES attempts!"
  log "Container logs:"
  docker logs $APP_NAME --tail 100 2>&1 | tee -a $LOG_FILE
  exit 1
fi

# ─── Verify API Endpoint ──────────────────────────────────────────
log "Testing API endpoint..."
API_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 http://localhost:${APP_PORT}/api/v1/ 2>/dev/null || echo "FAILED")

if echo "$API_RESPONSE" | grep -q '"success":true'; then
  log "API endpoint check passed! ✅"
else
  log "WARNING: API endpoint returned unexpected response:"
  log "$API_RESPONSE"
fi

# ─── Final Status ─────────────────────────────────────────────────
log "══════════════════════════════════════════════"
log "  DEPLOYMENT VALIDATED SUCCESSFULLY! 🚀"
log "  Container: $CONTAINER_ID"
log "  App: http://localhost:${APP_PORT}"
log "  Health: http://localhost:${APP_PORT}/health"
log "══════════════════════════════════════════════"

log "VALIDATE PHASE COMPLETE ✅"
exit 0
