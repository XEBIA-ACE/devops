# Project Structure

```
auth-service/
├── .github/
│   └── workflows/
│       └── ci.yml                          # CI/CD pipeline configuration
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── enterprise/
│   │   │           └── authservice/
│   │   │               ├── AuthServiceApplication.java    # Main application entry point
│   │   │               ├── config/                        # Configuration classes
│   │   │               │   ├── ApplicationConfig.java     # Application properties
│   │   │               │   └── SecurityConfig.java        # Security configuration
│   │   │               ├── controller/                    # REST controllers
│   │   │               │   ├── AuthController.java        # Authentication endpoints
│   │   │               │   └── HealthController.java      # Health check endpoints
│   │   │               ├── domain/
│   │   │               │   ├── dto/                       # Data Transfer Objects
│   │   │               │   │   ├── request/
│   │   │               │   │   │   ├── LoginRequest.java
│   │   │               │   │   │   ├── RefreshTokenRequest.java
│   │   │               │   │   │   └── RegisterRequest.java
│   │   │               │   │   └── response/
│   │   │               │   │       ├── AuthResponse.java
│   │   │               │   │       └── ErrorResponse.java
│   │   │               │   └── entity/                    # JPA entities
│   │   │               │       ├── AuditLog.java
│   │   │               │       ├── Permission.java
│   │   │               │       ├── RefreshToken.java
│   │   │               │       ├── Role.java
│   │   │               │       └── User.java
│   │   │               ├── exception/                     # Custom exceptions
│   │   │               │   ├── AuthenticationException.java
│   │   │               │   ├── GlobalExceptionHandler.java
│   │   │               │   ├── ResourceNotFoundException.java
│   │   │               │   └── ValidationException.java
│   │   │               ├── repository/                    # Data access layer
│   │   │               │   ├── AuditLogRepository.java
│   │   │               │   ├── PermissionRepository.java
│   │   │               │   ├── RefreshTokenRepository.java
│   │   │               │   ├── RoleRepository.java
│   │   │               │   └── UserRepository.java
│   │   │               ├── security/                      # Security components
│   │   │               │   ├── CustomUserDetailsService.java
│   │   │               │   ├── JwtAuthenticationFilter.java
│   │   │               │   ├── JwtTokenProvider.java
│   │   │               │   └── UserPrincipal.java
│   │   │               └── service/                       # Business logic
│   │   │                   ├── AuditService.java
│   │   │                   └── AuthService.java
│   │   └── resources/
│   │       ├── db/
│   │       │   └── migration/                             # Flyway migrations
│   │       │       ├── V1__initial_schema.sql
│   │       │       └── V2__seed_data.sql
│   │       ├── application.yml                            # Main configuration
│   │       ├── application-dev.yml                        # Development profile
│   │       └── application-prod.yml                       # Production profile
│   └── test/
│       ├── java/
│       │   └── com/
│       │       └── enterprise/
│       │           └── authservice/
│       │               ├── AuthServiceApplicationTests.java
│       │               ├── controller/
│       │               │   └── AuthControllerTest.java    # Controller tests
│       │               ├── security/
│       │               │   └── JwtTokenProviderTest.java  # Security tests
│       │               └── service/
│       │                   └── AuthServiceTest.java       # Service tests
│       └── resources/
│           └── application-test.yml                       # Test configuration
├── .dockerignore                                          # Docker ignore file
├── .env.example                                           # Environment variables template
├── .gitignore                                             # Git ignore file
├── API_DOCUMENTATION.md                                   # API documentation
├── CHANGELOG.md                                           # Version history
├── CONTRIBUTING.md                                        # Contribution guidelines
├── DEPLOYMENT.md                                          # Deployment guide
├── Dockerfile                                             # Docker image definition
├── LICENSE                                                # MIT license
├── Makefile                                               # Build automation
├── PROJECT_STRUCTURE.md                                   # This file
├── README.md                                              # Main documentation
├── docker-compose.yml                                     # Docker Compose configuration
├── pom.xml                                                # Maven project configuration
└── prometheus.yml                                         # Prometheus configuration
```

## Layer Descriptions

### API Layer (Controllers)
Handles HTTP requests and responses. Contains REST endpoints for authentication and health checks.

**Key Files:**
- `AuthController.java`: Authentication endpoints (register, login, logout, refresh)
- `HealthController.java`: Health check endpoints

### Business Logic Layer (Services)
Contains core business logic and orchestrates operations between controllers and repositories.

**Key Files:**
- `AuthService.java`: Authentication and user management logic
- `AuditService.java`: Audit logging functionality

### Security Layer
Implements JWT-based authentication, filters, and user details management.

**Key Files:**
- `JwtTokenProvider.java`: JWT token generation and validation
- `JwtAuthenticationFilter.java`: Request authentication filter
- `CustomUserDetailsService.java`: User details loading
- `UserPrincipal.java`: User principal implementation

### Data Access Layer (Repositories)
Provides database access using Spring Data JPA.

**Key Files:**
- `UserRepository.java`: User data access
- `RoleRepository.java`: Role data access
- `PermissionRepository.java`: Permission data access
- `RefreshTokenRepository.java`: Refresh token data access
- `AuditLogRepository.java`: Audit log data access

### Domain Layer (Entities & DTOs)
Contains domain models and data transfer objects.

**Entities:**
- `User.java`: User entity with roles and permissions
- `Role.java`: Role entity
- `Permission.java`: Permission entity
- `RefreshToken.java`: Refresh token entity
- `AuditLog.java`: Audit log entity

**DTOs:**
- Request DTOs: LoginRequest, RegisterRequest, RefreshTokenRequest
- Response DTOs: AuthResponse, ErrorResponse

### Configuration Layer
Application configuration and security setup.

**Key Files:**
- `SecurityConfig.java`: Spring Security configuration
- `ApplicationConfig.java`: Application properties binding
- `application.yml`: Main configuration file

### Database Layer
SQL migrations and schema definitions.

**Key Files:**
- `V1__initial_schema.sql`: Initial database schema
- `V2__seed_data.sql`: Default roles, permissions, and admin user

## Design Patterns Used

### 1. Repository Pattern
Abstracts data access logic from business logic.
```
Service -> Repository -> Database
```

### 2. DTO Pattern
Separates internal domain models from API contracts.
```
Controller -> DTO -> Service -> Entity
```

### 3. Dependency Injection
Uses Spring's IoC container for loose coupling.

### 4. Builder Pattern
Used in entities and DTOs for object construction.

### 5. Filter Chain Pattern
JWT authentication filter in Spring Security filter chain.

### 6. Strategy Pattern
Different authentication strategies (JWT, OAuth2).

## Key Technologies by Layer

### API Layer
- Spring Web MVC
- Spring Validation
- Springdoc OpenAPI

### Business Logic Layer
- Spring Boot
- Spring Transaction Management

### Security Layer
- Spring Security
- JWT (jjwt library)
- OAuth 2.0

### Data Access Layer
- Spring Data JPA
- Hibernate
- Flyway
- PostgreSQL

### Caching Layer
- Spring Cache
- Redis

### Testing Layer
- JUnit 5
- Mockito
- Spring Boot Test
- TestContainers

## Configuration Files

### Development
- `.env.example`: Template for environment variables
- `application-dev.yml`: Development-specific settings
- `docker-compose.yml`: Local development environment

### Production
- `application-prod.yml`: Production settings
- `Dockerfile`: Production-ready container image
- `prometheus.yml`: Monitoring configuration

### CI/CD
- `.github/workflows/ci.yml`: GitHub Actions pipeline
- `Makefile`: Build automation commands

## Entry Points

### Main Application
```
src/main/java/com/enterprise/authservice/AuthServiceApplication.java
```

### API Endpoints
```
/api/v1/auth/*          - Authentication endpoints
/actuator/*             - Monitoring endpoints
/swagger-ui.html        - API documentation
```

### Database Migrations
```
src/main/resources/db/migration/
```

## Build Artifacts

### Maven
```
target/                 - Compiled classes and JAR file
target/site/jacoco/     - Test coverage reports
```

### Docker
```
auth-service:latest     - Docker image
```

## Documentation Files

- `README.md`: Getting started, features, setup
- `API_DOCUMENTATION.md`: Complete API reference
- `DEPLOYMENT.md`: Deployment instructions
- `CONTRIBUTING.md`: Contribution guidelines
- `CHANGELOG.md`: Version history
- `PROJECT_STRUCTURE.md`: This file

## Additional Resources

### Auto-generated Documentation
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8080/api-docs`

### Monitoring
- Health: `http://localhost:8080/actuator/health`
- Metrics: `http://localhost:8080/actuator/metrics`
- Prometheus: `http://localhost:8080/actuator/prometheus`
