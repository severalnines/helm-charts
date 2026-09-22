#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHART_DIR="$ROOT_DIR/agent-operator/chart"

render() {
  helm template sweep-check "$CHART_DIR" "$@"
}

rendered="$(render)"
if ! grep -q -- '--sops-sweep-interval=10m' <<<"$rendered"; then
  echo "default render is missing --sops-sweep-interval=10m" >&2
  exit 1
fi

rendered="$(render --set sops.sweepInterval=30s)"
if ! grep -q -- '--sops-sweep-interval=30s' <<<"$rendered"; then
  echo "override render is missing --sops-sweep-interval=30s" >&2
  exit 1
fi

# Installer placeholders may explicitly supply empty rather than omit the key.
for enabled in true false; do
  rendered="$(render --set-string sops.sweepInterval= --set gitops.enabled=true --set "sops.enabled=$enabled")"
  if ! grep -q -- '--sops-sweep-interval=10m' <<<"$rendered"; then
    echo "empty sweep interval must preserve the default with sops.enabled=$enabled" >&2
    exit 1
  fi
done
