# ============================================
# Multi-stage Dockerfile for Go Application
# Optimized for security and minimal image size
# ============================================

# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

# Copy go mod files and download dependencies (cached layer)
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source code
COPY . .

# Build the application with optimizations
# -s -w: Strip debug information to reduce binary size
# -trimpath: Remove file system paths from binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-s -w -extldflags "-static"' \
    -trimpath \
    -o app \
    ./cmd/app

# Runtime stage - minimal distroless image
FROM gcr.io/distroless/static-debian12:nonroot

# Copy timezone data and certificates from builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /build/app /app

# Use non-root user (already set in distroless:nonroot)
USER nonroot:nonroot

# Expose application port
EXPOSE 8080

# Health check (if your app supports it)
# HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
#   CMD ["/app", "healthcheck"]

# Run the application
ENTRYPOINT ["/app"]
