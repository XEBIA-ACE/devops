# ================================================================
# Multi-Stage Dockerfile for Node.js Express API
# Optimized for Production with Security Best Practices
# ================================================================

# ----------------------------------------------------------------
# Stage 1: Dependencies
# ----------------------------------------------------------------
FROM node:18-alpine AS dependencies

# Install security updates
RUN apk upgrade --no-cache

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# ----------------------------------------------------------------
# Stage 2: Build
# ----------------------------------------------------------------
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies for build)
RUN npm ci --ignore-scripts

# Copy application source
COPY . .

# Build application (if build script exists)
RUN npm run build || echo "No build script found, skipping..."

# ----------------------------------------------------------------
# Stage 3: Production
# ----------------------------------------------------------------
FROM node:18-alpine AS production

# Build arguments
ARG NODE_ENV=production
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Labels for metadata
LABEL maintainer="DevOps Team <devops@company.com>"
LABEL org.opencontainers.image.title="Express API"
LABEL org.opencontainers.image.description="Node.js Express API Application"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.vendor="Your Company"

# Install security updates and dumb-init for proper signal handling
RUN apk upgrade --no-cache && \
    apk add --no-cache dumb-init

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy production dependencies from dependencies stage
COPY --from=dependencies --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy built application from build stage
COPY --from=build --chown=nodejs:nodejs /app/dist ./dist
COPY --from=build --chown=nodejs:nodejs /app/build ./build

# Copy necessary application files
COPY --chown=nodejs:nodejs package*.json ./
COPY --chown=nodejs:nodejs src ./src

# Set environment variables
ENV NODE_ENV=${NODE_ENV}
ENV PORT=3000

# Switch to non-root user
USER nodejs

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start the application
CMD ["node", "src/index.js"]
