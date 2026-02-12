.PHONY: help build test clean run docker-build docker-run docker-compose-up docker-compose-down

help:
	@echo "Available targets:"
	@echo "  build              - Build the application"
	@echo "  test               - Run tests"
	@echo "  test-coverage      - Run tests with coverage report"
	@echo "  clean              - Clean build artifacts"
	@echo "  run                - Run the application locally"
	@echo "  docker-build       - Build Docker image"
	@echo "  docker-run         - Run Docker container"
	@echo "  docker-compose-up  - Start all services with Docker Compose"
	@echo "  docker-compose-down - Stop all services"
	@echo "  format             - Format code"
	@echo "  lint               - Run linter"

build:
	@echo "Building application..."
	mvn clean package -DskipTests

test:
	@echo "Running tests..."
	mvn test

test-coverage:
	@echo "Running tests with coverage..."
	mvn clean test jacoco:report
	@echo "Coverage report: target/site/jacoco/index.html"

clean:
	@echo "Cleaning build artifacts..."
	mvn clean

run:
	@echo "Running application..."
	mvn spring-boot:run

docker-build:
	@echo "Building Docker image..."
	docker build -t auth-service:latest .

docker-run:
	@echo "Running Docker container..."
	docker run -d \
		--name auth-service \
		-p 8080:8080 \
		--env-file .env \
		auth-service:latest

docker-compose-up:
	@echo "Starting services with Docker Compose..."
	docker-compose up -d

docker-compose-down:
	@echo "Stopping services..."
	docker-compose down

docker-compose-logs:
	@echo "Viewing logs..."
	docker-compose logs -f auth-service

format:
	@echo "Formatting code..."
	mvn spotless:apply

lint:
	@echo "Running linter..."
	mvn checkstyle:check

db-migrate:
	@echo "Running database migrations..."
	mvn flyway:migrate

db-clean:
	@echo "Cleaning database..."
	mvn flyway:clean

install-deps:
	@echo "Installing dependencies..."
	mvn dependency:resolve

verify:
	@echo "Running verification..."
	mvn verify
