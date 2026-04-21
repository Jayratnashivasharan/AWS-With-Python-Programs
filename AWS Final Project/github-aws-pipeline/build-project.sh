#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  build-project.sh — Master Project Builder & Validator
#
#  Usage:
#    chmod +x build-project.sh
#    ./build-project.sh [--docker] [--install] [--test]
#
#  Flags:
#    --install   Install Node.js dependencies
#    --docker    Build & test Docker image locally
#    --test      Run application tests
#    --all       Do everything (install + test + docker)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✔  $1${NC}"; }
fail() { echo -e "${RED}  ✘  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}  ▸  $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠  $1${NC}"; }
step() { echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}"; }

# ─── Parse Flags ─────────────────────────────────────────────
DO_INSTALL=false; DO_DOCKER=false; DO_TEST=false

for arg in "$@"; do
  case $arg in
    --install) DO_INSTALL=true ;;
    --docker)  DO_DOCKER=true ;;
    --test)    DO_TEST=true ;;
    --all)     DO_INSTALL=true; DO_DOCKER=true; DO_TEST=true ;;
  esac
done

# ─── Banner ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   GitHub → AWS CodeDeploy Pipeline — Builder        ║"
echo "  ║   Node.js · Docker · ECR · CodeBuild · CodeDeploy   ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── 1. Project Root Check ───────────────────────────────────
step "1. Validating Project Root"

REQUIRED_FILES=(
  "Dockerfile"
  ".dockerignore"
  "buildspec.yml"
  "appspec.yml"
  "docker-compose.yml"
  ".env.example"
  ".gitignore"
  "app/package.json"
  "app/src/server.js"
  "app/src/config/app.js"
  "app/src/routes/api.js"
  "app/src/routes/health.js"
  "app/src/middleware/errorHandler.js"
  "app/src/middleware/requestLogger.js"
  "app/public/index.html"
  "app/public/css/style.css"
  "app/public/js/app.js"
  "aws/scripts/stop.sh"
  "aws/scripts/install.sh"
  "aws/scripts/after_install.sh"
  "aws/scripts/start.sh"
  "aws/scripts/validate.sh"
  "aws/nginx.conf"
  "docs/SETUP_GUIDE.md"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$f" ]; then
    ok "$f"
  else
    warn "MISSING: $f"
    ALL_OK=false
  fi
done

if [ "$ALL_OK" = false ]; then
  fail "Some required files are missing. Run the project setup first."
fi

# ─── 2. Make Scripts Executable ──────────────────────────────
step "2. Setting Script Permissions"
chmod +x aws/scripts/*.sh
ok "All deployment scripts are executable."

# ─── 3. Environment File ─────────────────────────────────────
step "3. Environment Configuration"
if [ ! -f ".env.local" ]; then
  cp .env.example .env.local
  ok "Created .env.local from .env.example"
  warn "Edit .env.local with your real AWS values before deploying."
else
  ok ".env.local already exists."
fi

# ─── 4. Check Prerequisites ──────────────────────────────────
step "4. Checking Prerequisites"

check_cmd() {
  if command -v "$1" &>/dev/null; then
    VER=$($1 --version 2>&1 | head -1)
    ok "$1 — $VER"
  else
    warn "$1 — NOT FOUND (install before deploying to AWS)"
  fi
}

check_cmd node
check_cmd npm
check_cmd docker
check_cmd aws
check_cmd git

# ─── 5. Install Node Dependencies ────────────────────────────
if [ "$DO_INSTALL" = true ]; then
  step "5. Installing Node.js Dependencies"
  cd app
  info "Running npm install in app/..."
  npm install
  ok "Dependencies installed."
  cd ..
else
  step "5. Node.js Dependencies (skipped — use --install)"
  info "Run with --install to install dependencies."
fi

# ─── 6. Run Tests ────────────────────────────────────────────
if [ "$DO_TEST" = true ]; then
  step "6. Running Tests"
  cd app
  if [ -f "node_modules/.bin/jest" ]; then
    npm test && ok "All tests passed." || warn "Tests failed (check output above)."
  else
    warn "Jest not found. Run --install first."
  fi
  cd ..
else
  step "6. Tests (skipped — use --test)"
fi

# ─── 7. Validate buildspec.yml ───────────────────────────────
step "7. Validating AWS Config Files"

# Check buildspec.yml has required keys
for key in "pre_build" "build" "post_build" "artifacts"; do
  if grep -q "$key" buildspec.yml; then
    ok "buildspec.yml: '$key' section found."
  else
    warn "buildspec.yml: '$key' section MISSING!"
  fi
done

# Check appspec.yml has required hooks
for hook in "ApplicationStop" "BeforeInstall" "ApplicationStart" "ValidateService"; do
  if grep -q "$hook" appspec.yml; then
    ok "appspec.yml: '$hook' hook found."
  else
    warn "appspec.yml: '$hook' hook MISSING!"
  fi
done

# ─── 8. Docker Build ─────────────────────────────────────────
if [ "$DO_DOCKER" = true ]; then
  step "8. Building Docker Image"
  
  if ! command -v docker &>/dev/null; then
    warn "Docker not found. Skipping image build."
  else
    IMAGE_TAG="github-aws-pipeline:local"
    info "Building image: $IMAGE_TAG"
    
    docker build -t $IMAGE_TAG . && ok "Docker image built: $IMAGE_TAG" || fail "Docker build failed!"
    
    # Show image size
    IMAGE_SIZE=$(docker image inspect $IMAGE_TAG --format='{{.Size}}' | awk '{printf "%.1f MB", $1/1024/1024}')
    ok "Image size: $IMAGE_SIZE"
    
    # ─── Run & Test Container ──────────────────────────────
    step "9. Testing Docker Container"
    
    # Stop any existing test container
    docker rm -f pipeline-test 2>/dev/null || true
    
    info "Starting test container on port 3333..."
    docker run -d \
      --name pipeline-test \
      -p 3333:3000 \
      -e NODE_ENV=production \
      -e PORT=3000 \
      $IMAGE_TAG
    
    info "Waiting for container to start (10s)..."
    sleep 10
    
    # Health check
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 5 --max-time 10 \
      http://localhost:3333/health 2>/dev/null || echo "000")
    
    if [ "$HEALTH" = "200" ]; then
      ok "Health check passed! (HTTP $HEALTH)"
    else
      warn "Health check returned HTTP $HEALTH (container may still be starting)"
      docker logs pipeline-test --tail 20
    fi
    
    # API check
    API=$(curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 5 --max-time 10 \
      http://localhost:3333/api/v1/ 2>/dev/null || echo "000")
    
    if [ "$API" = "200" ]; then
      ok "API endpoint passed! (HTTP $API)"
    else
      warn "API endpoint returned HTTP $API"
    fi
    
    info "Container logs:"
    docker logs pipeline-test --tail 10
    
    info "Stopping test container..."
    docker stop pipeline-test && docker rm pipeline-test
    ok "Test container cleaned up."
  fi
else
  step "8. Docker Build (skipped — use --docker)"
fi

# ─── Final Summary ───────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║              BUILD COMPLETE ✔                       ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}Next Steps:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Push to GitHub:          git push origin main"
echo -e "  ${CYAN}2.${NC} Set up AWS resources:    See docs/SETUP_GUIDE.md"
echo -e "  ${CYAN}3.${NC} Create ECR repository"
echo -e "  ${CYAN}4.${NC} Launch EC2 with IAM role"
echo -e "  ${CYAN}5.${NC} Create CodeDeploy app + deployment group"
echo -e "  ${CYAN}6.${NC} Create CodeBuild project"
echo -e "  ${CYAN}7.${NC} Create CodePipeline (Source → Build → Deploy)"
echo -e "  ${CYAN}8.${NC} Watch pipeline run at:   AWS Console → CodePipeline"
echo ""
echo -e "  ${BOLD}Quick local test:${NC}"
echo -e "    docker run -p 3000:3000 github-aws-pipeline:local"
echo -e "    open http://localhost:3000"
echo ""
echo -e "  ${BOLD}Full local stack (with NGINX):${NC}"
echo -e "    docker-compose up --build"
echo ""
