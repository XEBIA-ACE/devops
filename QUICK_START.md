# Quick Start Guide

Get the Authentication Service up and running in 5 minutes!

## Prerequisites

- Docker and Docker Compose installed
- 4GB+ RAM available
- Ports 8080, 5432, and 6379 available

## Option 1: One-Command Start (Recommended)

```bash
chmod +x start.sh
./start.sh
```

This script will:
1. Create `.env` file if it doesn't exist
2. Start all services (PostgreSQL, Redis, Application)
3. Display access URLs and credentials

## Option 2: Manual Start

### Step 1: Create Environment File

```bash
cp .env.example .env
```

### Step 2: Start Services

```bash
docker-compose up -d
```

### Step 3: Verify Services

```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs -f auth-service
```

## Accessing the Application

### API Endpoints
- **Base URL**: http://localhost:8080
- **Health Check**: http://localhost:8080/actuator/health
- **API Docs**: http://localhost:8080/swagger-ui.html

### Default Admin Account
- **Username**: `admin`
- **Email**: `admin@example.com`
- **Password**: `Admin123!`

## First API Call

### 1. Login as Admin

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "usernameOrEmail": "admin",
    "password": "Admin123!"
  }'
```

Response:
```json
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "...",
    "username": "admin",
    "email": "admin@example.com",
    "roles": ["ADMIN"]
  }
}
```

### 2. Register New User

```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "email": "john@example.com",
    "password": "SecurePass123!",
    "firstName": "John",
    "lastName": "Doe"
  }'
```

### 3. Access Protected Endpoint

```bash
# Replace YOUR_ACCESS_TOKEN with the token from login response
curl -X GET http://localhost:8080/api/v1/auth/me \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## Testing with Swagger UI

1. Open http://localhost:8080/swagger-ui.html
2. Click "Authorize" button
3. Login to get access token
4. Enter token in format: `Bearer YOUR_TOKEN`
5. Try API endpoints interactively

## Common Operations

### Stop Services
```bash
docker-compose down
```

### Restart Application Only
```bash
docker-compose restart auth-service
```

### View Application Logs
```bash
docker-compose logs -f auth-service
```

### Access Database
```bash
docker-compose exec postgres psql -U auth_user -d auth_service
```

### Access Redis CLI
```bash
docker-compose exec redis redis-cli
```

### Rebuild Application
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## Development Mode

### Run Locally (Without Docker)

1. Start dependencies:
```bash
docker-compose up -d postgres redis
```

2. Set environment variables:
```bash
export DB_HOST=localhost
export REDIS_HOST=localhost
export JWT_SECRET=your-secret-key-here
```

3. Run application:
```bash
mvn spring-boot:run
```

## Enable Optional Services

### Keycloak Identity Provider
```bash
docker-compose --profile keycloak up -d
```
Access: http://localhost:8180 (admin/admin)

### Monitoring Stack (Prometheus + Grafana)
```bash
docker-compose --profile monitoring up -d
```
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)

## Troubleshooting

### Port Already in Use
```bash
# Check what's using port 8080
lsof -i :8080

# Use different port
SERVER_PORT=8081 docker-compose up -d
```

### Services Won't Start
```bash
# Check logs
docker-compose logs

# Clean restart
docker-compose down -v
docker-compose up -d
```

### Database Connection Issues
```bash
# Check PostgreSQL is running
docker-compose ps postgres

# View PostgreSQL logs
docker-compose logs postgres
```

### Application Not Responding
```bash
# Check health endpoint
curl http://localhost:8080/actuator/health

# Check if running
docker-compose ps auth-service

# View application logs
docker-compose logs -f auth-service
```

## Next Steps

1. Read the [README.md](README.md) for detailed features
2. Check [API_DOCUMENTATION.md](API_DOCUMENTATION.md) for complete API reference
3. Review [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment
4. See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute

## Need Help?

- Check logs: `docker-compose logs -f`
- Health check: http://localhost:8080/actuator/health
- API documentation: http://localhost:8080/swagger-ui.html
- Open an issue on GitHub

## Clean Uninstall

```bash
# Stop and remove all containers, networks, and volumes
docker-compose down -v

# Remove Docker image
docker rmi auth-service:latest

# Remove project files
cd .. && rm -rf auth-service
```

---

**Congratulations!** 🎉 Your Authentication Service is now running!
