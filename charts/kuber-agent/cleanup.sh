#!/bin/bash

# Debug script for testing cleanup phases individually
# This removes Helm hooks so jobs run immediately instead of during pre-delete

set -e

echo "🔧 Cleanup Phase Debugging Tool"
echo "==============================="

# Chart directory is always where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR"

echo "📁 Using chart directory: $CHART_DIR"
echo "📁 Current working directory: $(pwd)"

# Verify Chart.yaml exists
if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
    echo "❌ Error: Chart.yaml not found in $CHART_DIR"
    echo "   The script should be located in the chart directory"
    exit 1
fi

# Determine target namespace - use environment variable or default
TARGET_NAMESPACE="${AGENT_NAMESPACE:-severalnines-system}"
echo "🎯 Target namespace: $TARGET_NAMESPACE"

# Verify the service account exists in target namespace
if ! kubectl get serviceaccount agent-operator-controller-manager -n "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    echo "⚠️  Warning: agent-operator-controller-manager service account not found in namespace '$TARGET_NAMESPACE'"
    echo "   You can specify the correct namespace with: AGENT_NAMESPACE=<namespace> $0 ..."
    echo "   Or install the agent-operator first"
fi

# Function to run a specific phase
run_phase() {
    local phase=$1
    local description=$2
    
    echo ""
    echo "🚀 Testing $description (Phase $phase)..."
    
    # Extract and apply the job without Helm hooks, using existing agent-operator service account
    helm template test-debug "$CHART_DIR" --set cleanup.enabled=true \
        | awk "/cleanup-phase${phase}-/,/^---\$/ {if(/^---\$/) exit; print}" \
        | sed '/helm.sh\/hook/d' \
        | sed "s/namespace: default/namespace: $TARGET_NAMESPACE/" \
        | kubectl apply -f -
    
    # Get job name
    job_name=$(kubectl get jobs -n "$TARGET_NAMESPACE" -l cleanup-phase="$phase" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$job_name" ]; then
        echo "📋 Job created: $job_name"
        
        # Wait for job to start and show status
        echo "⏳ Waiting for job to start..."
        kubectl wait --for=condition=Ready pod -n "$TARGET_NAMESPACE" -l job-name="$job_name" --timeout=60s || true
        
        echo "📝 Logs:"
        kubectl logs -n "$TARGET_NAMESPACE" -f job/$job_name || true
        
        # Wait for job completion
        echo "⏳ Waiting for job to complete..."
        kubectl wait --for=condition=Complete -n "$TARGET_NAMESPACE" job/$job_name --timeout=300s || true
        
        # Show final status
        echo "📊 Final status:"
        kubectl get job -n "$TARGET_NAMESPACE" $job_name
        
        # Show pod status if failed
        if kubectl get job -n "$TARGET_NAMESPACE" $job_name -o jsonpath='{.status.failed}' | grep -q "1"; then
            echo "❌ Job failed - Pod details:"
            kubectl get pods -n "$TARGET_NAMESPACE" -l job-name="$job_name"
            kubectl describe pods -n "$TARGET_NAMESPACE" -l job-name="$job_name"
        fi
    else
        echo "❌ No job found for phase $phase"
    fi
}

# Function to cleanup test jobs
cleanup_jobs() {
    echo ""
    echo "🧹 Cleaning up test jobs..."
    kubectl delete jobs -n "$TARGET_NAMESPACE" -l cleanup-phase --ignore-not-found=true
    echo "✅ Cleanup complete"
}

# Menu
case "${1:-menu}" in
    "0"|"validation")
        run_phase "0" "Validation"
        cleanup_jobs
        ;;
    "1"|"clusters")
        run_phase "1" "DatabaseClusters"
        cleanup_jobs
        ;;
    "2"|"operators") 
        run_phase "2" "DatabaseOperators"
        cleanup_jobs
        ;;
    "3"|"crds")
        run_phase "3" "CRDs"
        cleanup_jobs
        ;;
    "all")
        run_phase "0" "Validation"
        run_phase "1" "DatabaseClusters" 
        run_phase "2" "DatabaseOperators"
        run_phase "3" "CRDs"
        cleanup_jobs
        ;;
    "cleanup")
        cleanup_jobs
        ;;
    *)
        echo ""
        echo "Usage: $0 [phase]"
        echo "       AGENT_NAMESPACE=<namespace> $0 [phase]"
        echo ""
        echo "Phases:"
        echo "  0, validation  - Test validation phase"
        echo "  1, clusters    - Test DatabaseClusters cleanup"
        echo "  2, operators   - Test DatabaseOperators cleanup" 
        echo "  3, crds        - Test CRDs cleanup"
        echo "  all            - Test all phases in sequence"
        echo "  cleanup        - Remove test jobs"
        echo ""
        echo "Namespace:"
        echo "  - Default: 'severalnines-system'"
        echo "  - Override with AGENT_NAMESPACE environment variable"
        echo ""
        echo "Examples:"
        echo "  $0 1                                    # Test DatabaseClusters cleanup"
        echo "  $0 validation                           # Test validation phase"
        echo "  $0 all                                  # Test all phases"
        echo "  $0 cleanup                              # Clean up test jobs"
        echo "  AGENT_NAMESPACE=my-namespace $0 0       # Use specific namespace"
        ;;
esac 