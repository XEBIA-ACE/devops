#!/bin/bash
#
# Production Deployment Script for Data Processing Application
# This script deploys all Kubernetes manifests with proper ordering and verification
#
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="data-processing"
TIMEOUT=300 # 5 minutes
DRY_RUN="${DRY_RUN:-false}"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi

    # Check kustomize (optional)
    if command -v kustomize &> /dev/null; then
        log_success "kustomize found: $(kustomize version --short 2>/dev/null || echo 'unknown')"
    else
        log_warning "kustomize not found. Using kubectl with built-in kustomize."
    fi

    # Check if metrics-server is installed (for HPA)
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_warning "metrics-server not found. HPA may not work properly."
    fi

    log_success "Prerequisites check completed."
}

label_namespaces() {
    log_info "Labeling dependent namespaces for Network Policies..."

    kubectl label namespace kube-system name=kube-system --overwrite 2>/dev/null || true

    # Label monitoring namespace if it exists
    if kubectl get namespace monitoring &> /dev/null; then
        kubectl label namespace monitoring name=monitoring --overwrite
        log_success "Labeled monitoring namespace"
    else
        log_warning "monitoring namespace not found. Network policies for metrics scraping may not work."
    fi

    # Label other dependent namespaces if they exist
    for ns in database cache kafka; do
        if kubectl get namespace "$ns" &> /dev/null; then
            kubectl label namespace "$ns" name="$ns" --overwrite
            log_success "Labeled $ns namespace"
        fi
    done
}

deploy_resource() {
    local resource_file=$1
    local resource_name=$2

    log_info "Deploying $resource_name..."

    if [ "$DRY_RUN" = "true" ]; then
        kubectl apply -f "$resource_file" --dry-run=client
        log_success "$resource_name validated (dry-run)"
    else
        kubectl apply -f "$resource_file"
        log_success "$resource_name deployed"
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local condition=$3

    log_info "Waiting for $resource_type/$resource_name to be $condition..."

    if kubectl wait --for=condition="$condition" \
        "$resource_type/$resource_name" \
        -n "$NAMESPACE" \
        --timeout="${TIMEOUT}s" &> /dev/null; then
        log_success "$resource_type/$resource_name is $condition"
        return 0
    else
        log_error "$resource_type/$resource_name failed to become $condition"
        return 1
    fi
}

wait_for_deployment() {
    local deployment_name=$1

    log_info "Waiting for deployment/$deployment_name to be ready..."

    if kubectl rollout status deployment/"$deployment_name" \
        -n "$NAMESPACE" \
        --timeout="${TIMEOUT}s" &> /dev/null; then
        log_success "deployment/$deployment_name is ready"
        return 0
    else
        log_error "deployment/$deployment_name failed to become ready"
        kubectl get pods -n "$NAMESPACE" -l app="$deployment_name"
        return 1
    fi
}

verify_secrets() {
    log_info "Verifying required secrets..."

    local required_secrets=("haproxy-tls-secret" "data-processing-secrets")
    local missing_secrets=()

    for secret in "${required_secrets[@]}"; do
        if ! kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            missing_secrets+=("$secret")
        fi
    done

    if [ ${#missing_secrets[@]} -gt 0 ]; then
        log_error "Missing required secrets: ${missing_secrets[*]}"
        log_info "Please create secrets manually or wait for External Secrets Operator to sync."
        return 1
    fi

    log_success "All required secrets exist"
    return 0
}

deploy_all() {
    log_info "Starting deployment of data processing application..."

    # Deploy core resources
    deploy_resource "namespace.yaml" "Namespace and Resource Quotas"
    deploy_resource "rbac.yaml" "RBAC (ServiceAccounts, Roles, RoleBindings)"

    # Deploy configuration
    deploy_resource "configmap.yaml" "ConfigMaps"
    deploy_resource "secrets.yaml" "Secrets (External Secrets)"

    # Wait for External Secrets to sync
    if kubectl get externalsecret -n "$NAMESPACE" &> /dev/null; then
        log_info "Waiting for External Secrets to sync..."
        sleep 10

        if ! verify_secrets; then
            log_warning "Secrets not ready. Continuing anyway, but deployments may fail to start."
        fi
    fi

    # Deploy applications
    deploy_resource "deployment.yaml" "Deployments"
    deploy_resource "service.yaml" "Services"

    # Wait for deployments to be ready
    if [ "$DRY_RUN" != "true" ]; then
        wait_for_deployment "haproxy-ingress-controller" || true
        wait_for_deployment "data-processing-app" || true
        wait_for_deployment "default-backend" || true
    fi

    # Deploy ingress
    deploy_resource "ingress.yaml" "Ingress and TLS"

    # Deploy autoscaling and availability
    deploy_resource "hpa.yaml" "Horizontal Pod Autoscaler"
    deploy_resource "pdb.yaml" "Pod Disruption Budgets"

    # Deploy network policies last to avoid blocking deployment
    log_warning "Deploying Network Policies. This may temporarily disrupt connectivity."
    deploy_resource "network-policy.yaml" "Network Policies"

    log_success "Deployment completed!"
}

verify_deployment() {
    log_info "Verifying deployment..."

    # Check namespace
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE not found"
        return 1
    fi

    # Check pods
    log_info "Checking pod status..."
    kubectl get pods -n "$NAMESPACE"

    local not_running=$(kubectl get pods -n "$NAMESPACE" -o json | \
        jq -r '.items[] | select(.status.phase != "Running") | .metadata.name' | wc -l)

    if [ "$not_running" -gt 0 ]; then
        log_warning "$not_running pods are not in Running state"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running
    else
        log_success "All pods are running"
    fi

    # Check services
    log_info "Checking services..."
    kubectl get svc -n "$NAMESPACE"

    # Check ingress
    log_info "Checking ingress..."
    kubectl get ingress -n "$NAMESPACE"

    # Check HPA
    log_info "Checking HPA status..."
    kubectl get hpa -n "$NAMESPACE"

    # Check PDB
    log_info "Checking PDB status..."
    kubectl get pdb -n "$NAMESPACE"

    log_success "Verification completed"
}

run_smoke_tests() {
    log_info "Running smoke tests..."

    # Test 1: Check if HAProxy pods are ready
    local haproxy_ready=$(kubectl get pods -n "$NAMESPACE" -l app=haproxy-ingress \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c True || echo 0)

    if [ "$haproxy_ready" -gt 0 ]; then
        log_success "HAProxy ingress controller is ready"
    else
        log_error "HAProxy ingress controller is not ready"
    fi

    # Test 2: Check if application pods are ready
    local app_ready=$(kubectl get pods -n "$NAMESPACE" -l app=data-processing \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c True || echo 0)

    if [ "$app_ready" -gt 0 ]; then
        log_success "Application pods are ready"
    else
        log_error "Application pods are not ready"
    fi

    # Test 3: Test internal service connectivity
    log_info "Testing internal service connectivity..."
    if kubectl run test-pod --rm -i --restart=Never --image=curlimages/curl:latest \
        -n "$NAMESPACE" -- curl -s -o /dev/null -w "%{http_code}" \
        http://data-processing-app.data-processing.svc.cluster.local:8080/health 2>/dev/null | grep -q 200; then
        log_success "Internal service connectivity works"
    else
        log_warning "Internal service connectivity test failed or timed out"
    fi

    log_info "Smoke tests completed"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy data processing application to Kubernetes cluster.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Perform a dry-run without actually applying changes
    -v, --verify-only   Only verify existing deployment
    -s, --smoke-test    Run smoke tests after deployment
    -c, --check-only    Only check prerequisites

EXAMPLES:
    $0                  # Deploy all resources
    $0 --dry-run        # Validate manifests without applying
    $0 --verify-only    # Verify existing deployment
    $0 --smoke-test     # Deploy and run smoke tests

ENVIRONMENT VARIABLES:
    DRY_RUN=true        # Enable dry-run mode
    TIMEOUT=600         # Set timeout for waiting (seconds)

EOF
}

# Main execution
main() {
    local verify_only=false
    local smoke_test=false
    local check_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verify-only)
                verify_only=true
                shift
                ;;
            -s|--smoke-test)
                smoke_test=true
                shift
                ;;
            -c|--check-only)
                check_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Check prerequisites
    check_prerequisites

    if [ "$check_only" = "true" ]; then
        exit 0
    fi

    if [ "$verify_only" = "true" ]; then
        verify_deployment
        exit 0
    fi

    # Label namespaces for Network Policies
    label_namespaces

    # Deploy
    deploy_all

    # Verify
    echo ""
    verify_deployment

    # Run smoke tests if requested
    if [ "$smoke_test" = "true" ]; then
        echo ""
        run_smoke_tests
    fi

    echo ""
    log_success "Deployment script completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Check logs: kubectl logs -n $NAMESPACE -l app=haproxy-ingress --tail=100"
    echo "  2. Test endpoint: curl -k https://data-processing.example.com/health"
    echo "  3. Monitor HPA: kubectl get hpa -n $NAMESPACE -w"
    echo "  4. View metrics: kubectl port-forward -n $NAMESPACE svc/haproxy-ingress-stats 9101:9101"
}

# Run main function
main "$@"
