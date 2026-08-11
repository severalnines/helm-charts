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

# Prints the s9s:sops-pipeline ClusterRole document only. Keeping this parser
# inside the chart test lets us assert rule scope without relying on yq or a
# live Kubernetes API.
sops_pipeline_role() {
  awk '
    function flush() {
      if (kind == "ClusterRole" && name == "s9s:sops-pipeline") printf "%s", doc
      kind = ""; name = ""; doc = ""
    }
    $0 == "---" { flush(); next }
    {
      doc = doc $0 ORS
      if ($1 == "kind:" && kind == "") kind = $2
      if (kind != "" && $1 == "name:" && name == "") name = $2
    }
    END { flush() }
  '
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

# A managed namespace is managed: namespaces the operator explicitly listed
# in rbac.namespaces.targets get namespace-scoped write even in no-write
# mode. Restricted mode bans CLUSTER-WIDE write, not write inside the
# namespaces that were opted in by name. Asserted positively below.
no_write_namespaces="$(render_no_write | rolebinding_namespaces | sort -u)"
for namespace in observability sops-secrets; do
  if ! grep -qx "$namespace" <<<"$no_write_namespaces"; then
    echo "no-write mode did not render s9s-write RoleBinding in managed namespace $namespace" >&2
    exit 1
  fi
done

# argocd is never a managed namespace: it is the GitOps controller's own
# namespace, where the argoproj.io verbs in s9s:cluster-write would be live
# rather than inert. It must not receive write from this template.
if grep -qx 'argocd' <<<"$no_write_namespaces"; then
  echo "no-write mode rendered s9s-write RoleBinding in the GitOps controller namespace (argocd)" >&2
  exit 1
fi

# GitOps edit verbs (argoproj.io / fluxcd applications, helmreleases,
# kustomizations) live in the s9s:cluster-write ClusterRole. In no-write mode
# there must be NO ClusterRoleBinding to it — that is what "restricted" means.
# RoleBindings are allowed in exactly two places: the operator's own namespace
# (the agent manages its AppBundles/CCRs there) and the namespaces explicitly
# listed in rbac.namespaces.targets, which the operator opted in by name.
OPERATOR_NS=severalnines-system
MANAGED_NS_RE="observability|sops-secrets"

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

no_write_violations="$(render_no_write | cluster_write_bindings | grep -v "^RoleBinding $OPERATOR_NS\$" | grep -Ev "^RoleBinding ($MANAGED_NS_RE)\$" || true)"
if [[ -n "$no_write_violations" ]]; then
  echo "no-write mode rendered s9s:cluster-write bindings beyond the operator namespace (GitOps edit RBAC):" >&2
  echo "$no_write_violations" >&2
  exit 1
fi

no_write_flux_violations="$(render_no_write_flux | cluster_write_bindings | grep -v "^RoleBinding $OPERATOR_NS\$" | grep -Ev "^RoleBinding ($MANAGED_NS_RE)\$" || true)"
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

# In write mode the SA holds s9s:cluster-write cluster-wide (asserted above),
# so a per-namespace RoleBinding to the same role would be redundant. The
# template deliberately renders it only in no-write mode; this asserts it
# does not come back, so the two modes stay distinguishable.
write_namespaces="$(render_write | rolebinding_namespaces | sort -u)"
for namespace in observability sops-secrets; do
  if grep -qx "$namespace" <<<"$write_namespaces"; then
    echo "write mode rendered a redundant s9s-write RoleBinding in $namespace (cluster-wide binding already covers it)" >&2
    exit 1
  fi
done

# Restricted/no-write mode must never receive cluster-wide plaintext Secret
# reads from the SOPS role. Pattern A deliberately reports rbac_denied until
# namespace-scoped informers exist; the SopsSecret sweep capability remains
# cluster-wide. Unrestricted/write mode keeps the convenience Secret watch.
restricted_sops_role="$(render_no_write | sops_pipeline_role)"
if grep -Fq 'resources: ["secrets"]' <<<"$restricted_sops_role"; then
  echo "no-write mode rendered cluster-wide plaintext Secret read in s9s:sops-pipeline" >&2
  exit 1
fi
if ! grep -Fq 'resources: ["sopssecrets"]' <<<"$restricted_sops_role"; then
  echo "no-write mode did not retain cluster-wide SopsSecret read in s9s:sops-pipeline" >&2
  exit 1
fi

write_sops_role="$(render_write | sops_pipeline_role)"
if ! grep -Fq 'resources: ["secrets"]' <<<"$write_sops_role"; then
  echo "write mode did not retain cluster-wide plaintext Secret read in s9s:sops-pipeline" >&2
  exit 1
fi
