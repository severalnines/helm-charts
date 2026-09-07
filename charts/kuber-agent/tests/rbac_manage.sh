#!/usr/bin/env bash
# CLUS-8334: the s9s:rbac-manage grant (addon auxiliary Role/RoleBinding
# management in direct-apply mode). Contract under test:
#   1. write mode + default values → ClusterRole + write-SA binding rendered.
#   2. rbac.manageRbacObjects.enabled=false → grant absent even in write mode.
#   3. no-write mode NEVER renders the grant, even when the flag is forced on.
#   4. the grant never contains `escalate` or `bind` — the whole safety
#      argument for a cluster-wide RBAC-management grant is that Kubernetes
#      escalation prevention bounds it to the agent's own privileges.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHART_DIR="$ROOT_DIR/agent-operator/chart"

render() {
  helm template rbac-manage-check "$CHART_DIR" \
    --namespace severalnines-system \
    "$@"
}

# Prints "<kind> <name>" plus, for the binding, "subject <sa> <ns>" and
# "roleRef <name>"; for the role, each verbs line. Enough structure to assert
# presence, subject, and verb set without yq.
rbac_manage_docs() {
  awk '
    function flush() {
      if (kind == "ClusterRole" && name == "s9s:rbac-manage") printf "%s", doc
      if (kind == "ClusterRoleBinding" && ref == "s9s:rbac-manage") printf "%s", doc
      kind = ""; name = ""; ref = ""; in_ref = 0; doc = ""
    }
    $0 == "---" { flush(); next }
    {
      doc = doc $0 ORS
      if ($1 == "kind:" && kind == "") kind = $2
      if (kind != "" && $1 == "name:" && name == "") name = $2
      if ($0 == "roleRef:") in_ref = 1
      else if (in_ref && $1 == "name:") { ref = $2; in_ref = 0 }
    }
    END { flush() }
  '
}

# --- 1. write mode, defaults: grant + binding present, correct subject -----
write_docs="$(render --set mode.write.enabled=true | rbac_manage_docs)"
if ! grep -q 'kind: ClusterRole$' <<<"$write_docs"; then
  echo "write mode did not render the s9s:rbac-manage ClusterRole" >&2
  exit 1
fi
if ! grep -q 'kind: ClusterRoleBinding' <<<"$write_docs"; then
  echo "write mode did not render the s9s:rbac-manage ClusterRoleBinding" >&2
  exit 1
fi
if ! grep -q 'name: agent-operator-controller-manager-write' <<<"$write_docs"; then
  echo "s9s:rbac-manage binding does not target the write ServiceAccount" >&2
  exit 1
fi
if ! grep -Fq 'resources: ["roles", "rolebindings"]' <<<"$write_docs"; then
  echo "s9s:rbac-manage does not grant roles/rolebindings" >&2
  exit 1
fi

# --- 2. write mode, flag off: grant absent ---------------------------------
optout_docs="$(render --set mode.write.enabled=true \
  --set rbac.manageRbacObjects.enabled=false | rbac_manage_docs)"
if [[ -n "$optout_docs" ]]; then
  echo "rbac.manageRbacObjects.enabled=false still rendered the s9s:rbac-manage grant:" >&2
  echo "$optout_docs" >&2
  exit 1
fi

# --- 3. no-write mode never renders the grant, even forced on --------------
nowrite_docs="$(render --set mode.write.enabled=false \
  --set rbac.manageRbacObjects.enabled=true | rbac_manage_docs)"
if [[ -n "$nowrite_docs" ]]; then
  echo "no-write mode rendered the s9s:rbac-manage grant (must require mode.write.enabled):" >&2
  echo "$nowrite_docs" >&2
  exit 1
fi

# --- 4. no escalate/bind verb anywhere in the grant -------------------------
if grep -Eq '"(escalate|bind)"' <<<"$write_docs"; then
  echo "s9s:rbac-manage grants escalate/bind — this breaks the escalation-prevention safety bound" >&2
  exit 1
fi

# Belt-and-braces: escalate must not appear in ANY rendered RBAC rule of the
# full write-mode chart (a regression elsewhere would undermine the same
# argument: everything the agent can delegate must be bounded by what it holds).
full_render="$(render --set mode.write.enabled=true --set sops.enabled=true \
  --set gitops.enabled=true --set gitops.tool=argo \
  --set prometheusStack.enabled=true)"
if grep -Eq 'verbs:.*"escalate"' <<<"$full_render"; then
  echo "chart renders an RBAC rule with the escalate verb" >&2
  exit 1
fi

echo "rbac_manage.sh: OK"
