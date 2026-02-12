# API Documentation

Complete API reference for the Authentication Service.

## Base URL

```
Local: http://localhost:8080
Production: https://api.yourdomain.com
```

## Authentication

Most endpoints require authentication using JWT Bearer tokens:

```http
Authorization: Bearer <access_token>
```

## Error Responses

All error responses follow this format:

```json
{
  "status": 400,
  "error": "VALIDATION_ERROR",
  "message": "Validation failed",
  "path": "/api/v1/auth/register",
  "timestamp": "2024-01-15T10:30:00",
  "errors": {
    "email": ["Invalid email format"],
    "password": ["Password must contain at least one uppercase letter"]
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|------------|-------------|
| `VALIDATION_ERROR` | 400 | Request validation failed |
| `AUTHENTICATION_ERROR` | 401 | Authentication failed |
| `ACCESS_DENIED` | 403 | Insufficient permissions |
| `RESOURCE_NOT_FOUND` | 404 | Resource not found |
| `INTERNAL_SERVER_ERROR` | 500 | Server error |

## Endpoints

### 1. Register User

Create a new user account.

**Endpoint:** `POST /api/v1/auth/register`

**Request Body:**
```json
{
  "username": "johndoe",
  "email": "john.doe@example.com",
  "password": "SecurePassword123!",
  "firstName": "John",
  "lastName": "Doe",
  "phoneNumber": "+1234567890"
}
```

**Validation Rules:**
- `username`: 3-50 characters, alphanumeric with underscores and hyphens
- `email`: Valid email format
- `password`: 8-100 characters, must contain uppercase, lowercase, digit, and special character
- `firstName`, `lastName`, `phoneNumber`: Optional

**Success Response:** `201 Created`
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
    "firstName": "John",
    "lastName": "Doe",
    "roles": ["USER"],
    "permissions": []
  }
}
```

**Error Responses:**
- `400 Bad Request`: Validation failed or username/email already exists
- `500 Internal Server Error`: Server error

---

### 2. Login

Authenticate user and receive tokens.

**Endpoint:** `POST /api/v1/auth/login`

**Request Body:**
```json
{
  "usernameOrEmail": "johndoe",
  "password": "SecurePassword123!"
}
```

**Success Response:** `200 OK`
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
    "permissions": ["user:read"]
  }
}
```

**Error Responses:**
- `401 Unauthorized`: Invalid credentials
- `423 Locked`: Account locked due to failed login attempts

---

### 3. Refresh Token

Get a new access token using refresh token.

**Endpoint:** `POST /api/v1/auth/refresh`

**Request Body:**
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response:** `200 OK`
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

**Error Responses:**
- `401 Unauthorized`: Invalid or expired refresh token

---

### 4. Logout

Invalidate all refresh tokens for the authenticated user.

**Endpoint:** `POST /api/v1/auth/logout`

**Headers:**
```
Authorization: Bearer <access_token>
```

**Success Response:** `200 OK`
```json
{
  "message": "Logout successful"
}
```

**Error Responses:**
- `401 Unauthorized`: Missing or invalid token

---

### 5. Get Current User

Get authenticated user's information.

**Endpoint:** `GET /api/v1/auth/me`

**Headers:**
```
Authorization: Bearer <access_token>
```

**Success Response:** `200 OK`
```json
{
  "username": "johndoe",
  "authorities": [
    {
      "authority": "ROLE_USER"
    },
    {
      "authority": "user:read"
    }
  ]
}
```

**Error Responses:**
- `401 Unauthorized`: Missing or invalid token

---

### 6. Health Check

Check application health status.

**Endpoint:** `GET /api/v1/health`

**Success Response:** `200 OK`
```json
{
  "status": "UP",
  "timestamp": "2024-01-15T10:30:00",
  "service": "auth-service"
}
```

---

## OAuth 2.0 Endpoints

### Auth0 Login

**Endpoint:** `GET /api/v1/auth/oauth2/auth0`

Redirects to Auth0 login page.

### Keycloak Login

**Endpoint:** `GET /api/v1/auth/oauth2/keycloak`

Redirects to Keycloak login page.

---

## Rate Limiting

API endpoints are rate-limited to prevent abuse:

- Default: 60 requests per minute per IP
- Rate limit headers included in response:
  - `X-RateLimit-Limit`: Maximum requests allowed
  - `X-RateLimit-Remaining`: Remaining requests
  - `X-RateLimit-Reset`: Time when limit resets

**Rate Limit Exceeded Response:** `429 Too Many Requests`
```json
{
  "status": 429,
  "error": "RATE_LIMIT_EXCEEDED",
  "message": "Too many requests. Please try again later.",
  "path": "/api/v1/auth/login",
  "timestamp": "2024-01-15T10:30:00"
}
```

---

## CORS

The service supports CORS for specified origins.

Default allowed origins can be configured via `CORS_ALLOWED_ORIGINS` environment variable.

---

## Interactive API Documentation

OpenAPI/Swagger documentation is available at:

```
http://localhost:8080/swagger-ui.html
```

This provides:
- Interactive API testing
- Request/response examples
- Schema definitions
- Authentication testing

---

## Code Examples

### JavaScript/TypeScript

```typescript
// Register
const registerUser = async (userData) => {
  const response = await fetch('http://localhost:8080/api/v1/auth/register', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(userData),
  });
  return response.json();
};

// Login
const login = async (credentials) => {
  const response = await fetch('http://localhost:8080/api/v1/auth/login', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(credentials),
  });
  return response.json();
};

// Authenticated Request
const getProfile = async (accessToken) => {
  const response = await fetch('http://localhost:8080/api/v1/auth/me', {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
    },
  });
  return response.json();
};
```

### Python

```python
import requests

# Register
def register_user(user_data):
    response = requests.post(
        'http://localhost:8080/api/v1/auth/register',
        json=user_data
    )
    return response.json()

# Login
def login(credentials):
    response = requests.post(
        'http://localhost:8080/api/v1/auth/login',
        json=credentials
    )
    return response.json()

# Authenticated Request
def get_profile(access_token):
    headers = {'Authorization': f'Bearer {access_token}'}
    response = requests.get(
        'http://localhost:8080/api/v1/auth/me',
        headers=headers
    )
    return response.json()
```

### cURL

```bash
# Register
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "email": "john.doe@example.com",
    "password": "SecurePassword123!"
  }'

# Login
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "usernameOrEmail": "johndoe",
    "password": "SecurePassword123!"
  }'

# Get Profile
curl -X GET http://localhost:8080/api/v1/auth/me \
  -H "Authorization: Bearer <access_token>"
```

---

## Webhook Events (Future Feature)

Planned webhook events:
- `user.created`
- `user.login`
- `user.logout`
- `user.password_changed`
- `user.locked`

---

## Version History

- **v1.0.0**: Initial release with JWT authentication, OAuth 2.0 support
