#!/bin/bash

# Authentication Service Quick Start Script

set -e

echo "=================================="
echo "Authentication Service Quick Start"
echo "=================================="
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    echo "✓ .env file created"
    echo "⚠️  Please review and update the .env file with your configuration"
    echo ""
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "Starting services with Docker Compose..."
echo ""

# Start the services
docker-compose up -d

echo ""
echo "✓ Services are starting..."
echo ""

# Wait for services to be ready
echo "Waiting for services to be healthy..."
sleep 10

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo "✓ Services are running"
else
    echo "❌ Some services failed to start. Check logs with: docker-compose logs"
    exit 1
fi

echo ""
echo "=================================="
echo "Service Information"
echo "=================================="
echo ""
echo "Application:"
echo "  URL: http://localhost:8080"
echo "  Health: http://localhost:8080/actuator/health"
echo ""
echo "API Documentation:"
echo "  Swagger UI: http://localhost:8080/swagger-ui.html"
echo "  OpenAPI JSON: http://localhost:8080/api-docs"
echo ""
echo "Database:"
echo "  PostgreSQL: localhost:5432"
echo "  Database: auth_service"
echo ""
echo "Cache:"
echo "  Redis: localhost:6379"
echo ""
echo "Default Admin Credentials:"
echo "  Username: admin"
echo "  Password: Admin123!"
echo ""
echo "=================================="
echo "Useful Commands"
echo "=================================="
echo ""
echo "View logs:"
echo "  docker-compose logs -f auth-service"
echo ""
echo "Stop services:"
echo "  docker-compose down"
echo ""
echo "Restart services:"
echo "  docker-compose restart"
echo ""
echo "View API documentation:"
echo "  open http://localhost:8080/swagger-ui.html"
echo ""
echo "=================================="
echo ""
echo "✓ Authentication Service is ready!"
echo ""
