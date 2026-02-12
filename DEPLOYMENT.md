# Deployment Guide

This guide provides instructions for deploying the Authentication Service to various environments.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Configuration](#environment-configuration)
- [Docker Deployment](#docker-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Cloud Deployments](#cloud-deployments)
- [Production Checklist](#production-checklist)

## Prerequisites

- Java 17 runtime
- PostgreSQL 16+
- Redis 7+
- Docker (for containerized deployment)
- Kubernetes cluster (for K8s deployment)

## Environment Configuration

### Required Environment Variables

```bash
# Application
SPRING_PROFILES_ACTIVE=prod
SERVER_PORT=8080

# Database
DB_HOST=your-db-host
DB_PORT=5432
DB_NAME=auth_service
DB_USERNAME=auth_user
DB_PASSWORD=<secure-password>

# JWT
JWT_SECRET=<your-256-bit-secret>
JWT_EXPIRATION=3600000
JWT_REFRESH_EXPIRATION=604800000

# Redis
REDIS_HOST=your-redis-host
REDIS_PORT=6379
REDIS_PASSWORD=<secure-password>
```

### Security Considerations

1. **Never commit secrets to version control**
2. Use environment-specific configuration management
3. Rotate secrets regularly
4. Use strong passwords (minimum 16 characters)
5. Enable TLS for all connections

## Docker Deployment

### Build Image

```bash
docker build -t auth-service:1.0.0 .
```

### Run Container

```bash
docker run -d \
  --name auth-service \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_HOST=postgres-host \
  -e DB_PASSWORD=secure-password \
  -e JWT_SECRET=your-secret \
  auth-service:1.0.0
```

### Docker Compose Production

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    restart: unless-stopped

  auth-service:
    image: auth-service:1.0.0
    environment:
      SPRING_PROFILES_ACTIVE: prod
      DB_HOST: postgres
      DB_PASSWORD: ${DB_PASSWORD}
      REDIS_HOST: redis
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      JWT_SECRET: ${JWT_SECRET}
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - redis
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

Deploy:
```bash
docker-compose -f docker-compose.prod.yml up -d
```

## Kubernetes Deployment

### Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: auth-service
```

### Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secrets
  namespace: auth-service
type: Opaque
stringData:
  db-password: <base64-encoded-password>
  jwt-secret: <base64-encoded-secret>
  redis-password: <base64-encoded-password>
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-service-config
  namespace: auth-service
data:
  application.yml: |
    spring:
      profiles:
        active: prod
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: auth-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: auth-service:1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: auth-service-secrets
              key: db-password
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: auth-service-secrets
              key: jwt-secret
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: auth-service
spec:
  selector:
    app: auth-service
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
```

### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auth-service-ingress
  namespace: auth-service
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - auth.yourdomain.com
    secretName: auth-tls
  rules:
  - host: auth.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 80
```

### Apply Kubernetes Resources

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

## Cloud Deployments

### AWS ECS

1. Create ECR repository
2. Push Docker image to ECR
3. Create ECS task definition
4. Create ECS service
5. Configure Application Load Balancer
6. Set up RDS PostgreSQL
7. Set up ElastiCache Redis

### Google Cloud Run

```bash
# Build and push
gcloud builds submit --tag gcr.io/PROJECT_ID/auth-service

# Deploy
gcloud run deploy auth-service \
  --image gcr.io/PROJECT_ID/auth-service \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### Azure Container Instances

```bash
az container create \
  --resource-group auth-service-rg \
  --name auth-service \
  --image auth-service:1.0.0 \
  --dns-name-label auth-service \
  --ports 8080
```

## Production Checklist

### Before Deployment

- [ ] All tests passing
- [ ] Security scan completed
- [ ] Environment variables configured
- [ ] Database migrations tested
- [ ] SSL/TLS certificates configured
- [ ] Monitoring and alerting set up
- [ ] Backup strategy implemented
- [ ] Disaster recovery plan documented

### Security

- [ ] Change default admin password
- [ ] Rotate JWT secret
- [ ] Enable HTTPS only
- [ ] Configure CORS properly
- [ ] Set up rate limiting
- [ ] Enable audit logging
- [ ] Configure firewall rules
- [ ] Set up WAF (if applicable)

### Performance

- [ ] Configure connection pooling
- [ ] Enable Redis caching
- [ ] Set up CDN (if applicable)
- [ ] Configure auto-scaling
- [ ] Optimize database indexes
- [ ] Enable compression

### Monitoring

- [ ] Health checks configured
- [ ] Metrics collection enabled
- [ ] Log aggregation set up
- [ ] Alerts configured
- [ ] Dashboard created

### Backup and Recovery

- [ ] Database backup scheduled
- [ ] Backup retention policy set
- [ ] Recovery procedure tested
- [ ] Disaster recovery plan documented

## Rollback Procedure

### Docker

```bash
docker-compose down
docker-compose up -d --force-recreate
```

### Kubernetes

```bash
kubectl rollout undo deployment/auth-service -n auth-service
```

## Monitoring Deployment

```bash
# Docker
docker-compose logs -f auth-service

# Kubernetes
kubectl logs -f deployment/auth-service -n auth-service

# Check health
curl https://auth.yourdomain.com/actuator/health
```

## Post-Deployment Verification

1. Check application health endpoint
2. Verify database connectivity
3. Test authentication endpoints
4. Check metrics in Prometheus
5. Review application logs
6. Verify SSL certificate
7. Test rate limiting
8. Verify backup jobs

## Troubleshooting

### Application Won't Start

- Check logs for errors
- Verify environment variables
- Check database connectivity
- Verify Redis connectivity

### High Memory Usage

- Review heap size settings
- Check for memory leaks
- Analyze heap dump
- Adjust JVM parameters

### Slow Performance

- Check database query performance
- Verify Redis connection
- Review connection pool settings
- Check resource limits

## Support

For deployment issues, consult:
- Application logs
- Health check endpoints
- Monitoring dashboards
- Infrastructure team
