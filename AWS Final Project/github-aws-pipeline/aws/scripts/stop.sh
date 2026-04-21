#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# stop.sh - ApplicationStop Hook
# Gracefully stops the running Docker container
# ═══════════════════════════════════════════════════════════════

set -e

APP_NAME="github-aws-pipeline-app"
LOG_FILE="/var/log/codedeploy-${APP_NAME}.log"
TIMEOUT=30

echo "════════════════════════════════════════" | tee -a $LOG_FILE
echo "  [$(date)] STOP PHASE STARTED" | tee -a $LOG_FILE
echo "════════════════════════════════════════" | tee -a $LOG_FILE

# Function to log with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check if container is running
CONTAINER_ID=$(docker ps -q --filter "name=${APP_NAME}" 2>/dev/null || echo "")

if [ -n "$CONTAINER_ID" ]; then
  log "Found running container: $CONTAINER_ID"
  log "Sending SIGTERM for graceful shutdown (timeout: ${TIMEOUT}s)..."
  
  # Graceful stop with timeout
  docker stop --time=$TIMEOUT $CONTAINER_ID && \
    log "Container stopped gracefully." || \
    log "Graceful stop timed out, forcing kill..."
  
  # Remove the stopped container
  docker rm -f $APP_NAME 2>/dev/null && \
    log "Container removed." || \
    log "Container already removed."
else
  log "No running container found for: ${APP_NAME}"
  log "Skipping stop (nothing to stop)."
fi

# Also clean up any dangling containers with the same name
docker rm -f $APP_NAME 2>/dev/null || true

log "STOP PHASE COMPLETE"
exit 0
