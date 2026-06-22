#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHART_DIR="$ROOT_DIR/agent-operator/chart"

render_no_write() {
  helm template rbac-check "$CHART_DIR" \
    --namespace severalnines-system \
    --set mode.write.enabled=false \
    --set gitops.enabled=true \
    --set gitops.tool=argo \
    --set gitops.argo.namespace=argocd \
    --set rbac.namespaces.targets='{observability,sops-secrets}' \
    --set prometheusStack.enabled=true \
    --set prometheusStack.prometheus.enabled=true \
    --set prometheusStack.grafana.enabled=true \
    --set sops.enabled=true
}

render_write() {
  helm template rbac-check "$CHART_DIR" \
    --namespace severalnines-system \
    --set mode.write.enabled=true \
    --set gitops.enabled=true \
    --set gitops.tool=argo \
    --set gitops.argo.namespace=argocd \
    --set rbac.namespaces.targets='{observability,sops-secrets}' \
    --set prometheusStack.enabled=true \
    --set sops.enabled=true
}

render_no_write_flux() {
  helm template rbac-check "$CHART_DIR" \
    --namespace severalnines-system \
    --set mode.write.enabled=false \
    --set gitops.enabled=true \
    --set gitops.tool=flux \
    --set gitops.flux.namespace=flux-system \
    --set rbac.namespaces.targets='{observability,sops-secrets}' \
    --set prometheusStack.enabled=true \
    --set sops.enabled=true
}

rolebinding_namespaces() {
  awk '
    $0 == "kind: RoleBinding" { in_rb = 1; name = ""; namespace = ""; next }
    in_rb && $1 == "name:" && name == "" { name = $2 }
    in_rb && $1 == "namespace:" && namespace == "" { namespace = $2 }
    in_rb && $0 == "---" {
      if (name == "s9s-write") print namespace
      in_rb = 0
    }
    END {
      if (in_rb && name == "s9s-write") print namespace
    }
  '
}

no_write_namespaces="$(render_no_write | rolebinding_namespaces | sort -u)"
if grep -Eq '^(argocd|observability|sops-secrets)$' <<<"$no_write_namespaces"; then
  echo "no-write mode rendered s9s-write RoleBinding in addon target namespace(s):" >&2
  grep -E '^(argocd|observability|sops-secrets)$' <<<"$no_write_namespaces" >&2
  exit 1
fi

# GitOps edit verbs (argoproj.io / fluxcd applications, helmreleases,
# kustomizations) live in the s9s:cluster-write ClusterRole. In no-write mode
# the only allowed binding to it is the RoleBinding in the operator's own
# namespace (the agent must manage its own AppBundles/CCRs there); no
# ClusterRoleBinding, no RoleBinding in any other namespace.
OPERATOR_NS=severalnines-system

# Prints "<bindingKind> <namespace>" for every (Cluster)RoleBinding whose
# roleRef targets s9s:cluster-write. ClusterRoleBindings print an empty
# namespace.
cluster_write_bindings() {
  awk '
    function flush() {
      if (kind != "" && ref == "s9s:cluster-write") print kind, ns
      kind = ""; ns = ""; ref = ""; in_ref = 0; seen_ref = 0
    }
    $0 == "---" { flush(); next }
    kind == "" && $1 == "kind:" && ($2 == "RoleBinding" || $2 == "ClusterRoleBinding") { kind = $2; next }
    kind != "" && !seen_ref && ns == "" && $1 == "namespace:" { ns = $2; next }
    kind != "" && $0 == "roleRef:" { in_ref = 1; seen_ref = 1; next }
    in_ref && $1 == "name:" { ref = $2; in_ref = 0; next }
    END { flush() }
  '
}

no_write_violations="$(render_no_write | cluster_write_bindings | grep -v "^RoleBinding $OPERATOR_NS\$" || true)"
if [[ -n "$no_write_violations" ]]; then
  echo "no-write mode rendered s9s:cluster-write bindings beyond the operator namespace (GitOps edit RBAC):" >&2
  echo "$no_write_violations" >&2
  exit 1
fi

no_write_flux_violations="$(render_no_write_flux | cluster_write_bindings | grep -v "^RoleBinding $OPERATOR_NS\$" || true)"
if [[ -n "$no_write_flux_violations" ]]; then
  echo "no-write Flux mode rendered s9s:cluster-write bindings beyond the operator namespace (GitOps edit RBAC):" >&2
  echo "$no_write_flux_violations" >&2
  exit 1
fi

# Positive check: write mode must bind s9s:cluster-write cluster-wide. This
# also guards the binding parser above against rendering/format drift — if it
# stops matching, this fails rather than the no-write checks passing
# vacuously.
if ! render_write | cluster_write_bindings | grep -q '^ClusterRoleBinding'; then
  echo "write mode did not render a ClusterRoleBinding to s9s:cluster-write" >&2
  exit 1
fi

write_namespaces="$(render_write | rolebinding_namespaces | sort -u)"
for namespace in observability sops-secrets; do
  if ! grep -qx "$namespace" <<<"$write_namespaces"; then
    echo "write mode did not render expected s9s-write RoleBinding in $namespace" >&2
    exit 1
  fi
done
