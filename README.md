# Authentication Service

A production-ready, enterprise-grade authentication and authorization service built with Spring Boot, supporting OAuth 2.0, JWT, Auth0, and Keycloak integration.

## Features

- **JWT Authentication**: Secure token-based authentication with access and refresh tokens
- **OAuth 2.0 Integration**: Support for Auth0 and Keycloak identity providers
- **Role-Based Access Control (RBAC)**: Fine-grained permissions and role management
- **User Management**: Complete user lifecycle management with email verification
- **Security**: BCrypt password hashing, account locking, failed login tracking
- **Audit Logging**: Comprehensive audit trail of all authentication events
- **Caching**: Redis-based caching for improved performance
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **API Documentation**: OpenAPI/Swagger documentation
- **Production Ready**: Docker support, health checks, structured logging

## Technology Stack

- **Framework**: Spring Boot 3.2.2
- **Language**: Java 17
- **Security**: Spring Security, OAuth 2.0, JWT
- **Database**: PostgreSQL with Flyway migrations
- **Cache**: Redis
- **Identity Providers**: Auth0, Keycloak
- **Monitoring**: Prometheus, Grafana, Spring Actuator
- **Documentation**: Springdoc OpenAPI
- **Testing**: JUnit 5, Mockito, TestContainers
- **Build**: Maven
- **Containerization**: Docker, Docker Compose

## Architecture

### Clean Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│              API Layer (Controllers)                 │
│  - AuthController, HealthController                  │
└─────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────┐
│           Business Logic (Services)                  │
│  - AuthService, AuditService                         │
└─────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────┐
│          Data Access (Repositories)                  │
│  - UserRepository, RoleRepository, etc.              │
└─────────────────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────┐
│              Database (PostgreSQL)                   │
└─────────────────────────────────────────────────────┘
```

### Security Flow

```
Client Request → JWT Filter → Spring Security → Controller → Service → Repository → Database
                     ↓
              Token Validation
                     ↓
           SecurityContext Setup
```

## Getting Started

### Prerequisites

- Java 17 or higher
- Maven 3.9+
- Docker and Docker Compose (for containerized setup)
- PostgreSQL 16+ (if running locally)
- Redis 7+ (if running locally)

### Quick Start with Docker

1. Clone the repository:
```bash
git clone <repository-url>
cd auth-service
```

2. Copy the environment file and configure:
```bash
cp .env.example .env
# Edit .env with your configuration
```

3. Start all services:
```bash
docker-compose up -d
```

4. Access the application:
- API: http://localhost:8080
- Swagger UI: http://localhost:8080/swagger-ui.html
- Health Check: http://localhost:8080/actuator/health

### Local Development Setup

1. Start dependencies:
```bash
docker-compose up -d postgres redis
```

2. Configure environment variables:
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=auth_service
export DB_USERNAME=auth_user
export DB_PASSWORD=changeme
export REDIS_HOST=localhost
export JWT_SECRET=your-256-bit-secret-key-change-this-in-production
```

3. Build and run:
```bash
mvn clean install
mvn spring-boot:run
```

### Running with Keycloak

```bash
docker-compose --profile keycloak up -d
```

Access Keycloak at http://localhost:8180 (admin/admin)

### Running with Monitoring

```bash
docker-compose --profile monitoring up -d
```

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SPRING_PROFILES_ACTIVE` | Active Spring profile | `dev` |
| `SERVER_PORT` | Application port | `8080` |
| `DB_HOST` | Database host | `localhost` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `auth_service` |
| `DB_USERNAME` | Database username | `auth_user` |
| `DB_PASSWORD` | Database password | `changeme` |
| `JWT_SECRET` | JWT signing secret (256-bit) | Required |
| `JWT_EXPIRATION` | Access token expiration (ms) | `86400000` |
| `AUTH0_ENABLED` | Enable Auth0 integration | `false` |
| `AUTH0_DOMAIN` | Auth0 domain | - |
| `KEYCLOAK_ENABLED` | Enable Keycloak integration | `false` |
| `KEYCLOAK_AUTH_SERVER_URL` | Keycloak server URL | - |
| `REDIS_HOST` | Redis host | `localhost` |

See `.env.example` for complete list.

### Profiles

- `dev`: Development profile with debug logging
- `prod`: Production profile with optimized settings
- `test`: Testing profile with H2 database

## API Documentation

### Authentication Endpoints

#### Register User
```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "username": "johndoe",
  "email": "john.doe@example.com",
  "password": "SecurePassword123!",
  "firstName": "John",
  "lastName": "Doe"
}
```

**Response:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "username": "johndoe",
    "email": "john.doe@example.com",
    "roles": ["USER"],
    "permissions": []
  }
}
```

#### Login
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "usernameOrEmail": "johndoe",
  "password": "SecurePassword123!"
}
```

#### Refresh Token
```http
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

#### Logout
```http
POST /api/v1/auth/logout
Authorization: Bearer {accessToken}
```

#### Get Current User
```http
GET /api/v1/auth/me
Authorization: Bearer {accessToken}
```

### Using the Access Token

Include the access token in the Authorization header:
```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Database Schema

### Tables

- **users**: User accounts and authentication data
- **roles**: Role definitions
- **permissions**: Permission definitions
- **user_roles**: User-role associations
- **role_permissions**: Role-permission associations
- **refresh_tokens**: Active refresh tokens
- **audit_logs**: Audit trail of authentication events

### Default Data

The service initializes with:
- **Roles**: USER, ADMIN, MODERATOR
- **Admin User**:
  - Username: `admin`
  - Password: `Admin123!`
  - Email: `admin@example.com`

## Security Features

### Password Requirements

- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one digit
- At least one special character (@$!%*?&)

### Account Security

- Failed login tracking (locks after 5 attempts)
- Password expiration tracking
- Email verification support
- Account status management

### Token Management

- Short-lived access tokens (default: 24 hours)
- Long-lived refresh tokens (default: 7 days)
- Token revocation on logout
- Automatic cleanup of expired tokens

## Monitoring and Observability

### Health Checks

```bash
# Application health
curl http://localhost:8080/actuator/health

# Liveness probe
curl http://localhost:8080/actuator/health/liveness

# Readiness probe
curl http://localhost:8080/actuator/health/readiness
```

### Metrics

Prometheus metrics available at: http://localhost:8080/actuator/prometheus

Key metrics:
- `http_server_requests_seconds`: Request duration
- `jvm_memory_used_bytes`: JVM memory usage
- `system_cpu_usage`: CPU usage
- Custom business metrics

### Logging

Structured JSON logging with correlation IDs for request tracing.

Log levels:
- `ERROR`: Critical errors requiring attention
- `WARN`: Warning conditions
- `INFO`: Informational messages
- `DEBUG`: Debug information (dev profile only)

## Testing

### Run All Tests
```bash
mvn test
```

### Run Specific Test Class
```bash
mvn test -Dtest=AuthServiceTest
```

### Run Integration Tests
```bash
mvn verify
```

### Test Coverage
```bash
mvn jacoco:report
# Report: target/site/jacoco/index.html
```

## Deployment

### Building for Production

```bash
mvn clean package -Pprod
```

### Docker Build

```bash
docker build -t auth-service:latest .
```

### Kubernetes Deployment

Example Kubernetes manifests are available in the `k8s/` directory (create if needed).

Key considerations:
- Use Kubernetes Secrets for sensitive data
- Configure resource limits and requests
- Set up horizontal pod autoscaling
- Configure persistent volumes for PostgreSQL
- Use ingress for external access

## CI/CD Integration

### GitHub Actions Example

```yaml
name: CI/CD

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up JDK 17
        uses: actions/setup-java@v2
        with:
          java-version: '17'
      - name: Build with Maven
        run: mvn clean package
      - name: Run tests
        run: mvn test
      - name: Build Docker image
        run: docker build -t auth-service:${{ github.sha }} .
```

## OAuth 2.0 Integration

### Auth0 Setup

1. Create an Auth0 application
2. Configure environment variables:
```bash
AUTH0_ENABLED=true
AUTH0_DOMAIN=your-domain.auth0.com
AUTH0_CLIENT_ID=your-client-id
AUTH0_CLIENT_SECRET=your-client-secret
AUTH0_AUDIENCE=your-api-identifier
```

### Keycloak Setup

1. Create a Keycloak realm
2. Create a client in the realm
3. Configure environment variables:
```bash
KEYCLOAK_ENABLED=true
KEYCLOAK_AUTH_SERVER_URL=http://localhost:8180
KEYCLOAK_REALM=auth-service
KEYCLOAK_CLIENT_ID=auth-service-client
KEYCLOAK_CLIENT_SECRET=your-client-secret
```

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker-compose ps postgres

# View PostgreSQL logs
docker-compose logs postgres

# Connect to database
docker-compose exec postgres psql -U auth_user -d auth_service
```

### Redis Connection Issues

```bash
# Check Redis is running
docker-compose ps redis

# Test Redis connection
docker-compose exec redis redis-cli ping
```

### Application Logs

```bash
# View application logs
docker-compose logs -f auth-service

# View last 100 lines
docker-compose logs --tail=100 auth-service
```

## Performance Tuning

### JVM Options

```bash
# Adjust heap size
JAVA_OPTS="-Xms512m -Xmx2g"

# Enable G1GC
JAVA_OPTS="-XX:+UseG1GC"

# Container support
JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

### Database Connection Pool

Adjust in `application.yml`:
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- GitHub Issues: [Create an issue]
- Documentation: See `/docs` directory
- API Documentation: http://localhost:8080/swagger-ui.html

## Changelog

### Version 1.0.0
- Initial release
- JWT authentication
- OAuth 2.0 support (Auth0, Keycloak)
- Role-based access control
- Audit logging
- Docker support
- Comprehensive testing
