# ═══════════════════════════════════════════════════════════════
# Stage 1: Builder
# Install all dependencies including dev dependencies for builds
# ═══════════════════════════════════════════════════════════════
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies (needed for some native modules)
RUN apk add --no-cache python3 make g++

# Copy package files first (for Docker layer caching)
COPY package*.json ./

# Install ALL dependencies (including devDependencies for build step)
RUN npm ci --only=production && npm cache clean --force

# ═══════════════════════════════════════════════════════════════
# Stage 2: Production Image
# Minimal, secure, optimized final image
# ═══════════════════════════════════════════════════════════════
FROM node:18-alpine AS production

# Install security updates and dumb-init for proper signal handling
RUN apk add --no-cache \
    dumb-init \
    curl \
    && apk upgrade --no-cache

# Create non-root user for security (never run as root in production)
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Copy production node_modules from builder stage
COPY --from=builder --chown=nodeuser:nodejs /app/node_modules ./node_modules

# Copy application source code
COPY --chown=nodeuser:nodejs app/src ./src
COPY --chown=nodeuser:nodejs app/src/../public ./public
COPY --chown=nodeuser:nodejs app/package.json ./

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

# Switch to non-root user
USER nodeuser

# Expose application port
EXPOSE 3000

# Health check - ensures container is healthy before routing traffic
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=30s \
            --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init as PID 1 to properly handle signals
ENTRYPOINT ["dumb-init", "--"]

# Start the application
CMD ["node", "src/server.js"]
