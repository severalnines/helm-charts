#!/usr/bin/env bash
# The prometheusStack.grafana.gatewayRoute toggle (publish Grafana through
# the shared cc-gateway). Contract under test:
#   1. defaults → PROMETHEUS_STACK_GRAFANA_GATEWAY_ROUTE renders "true"
#      (default-true boolean: the env var must ALWAYS be set explicitly,
#      because if-true gating cannot express "false" — same shape as
#      PROMETHEUS_STACK_DASHBOARDS_ENABLED).
#   2. gatewayRoute=false → the env var renders "false" (not omitted!),
#      so the addon's envBoolDefault sees the opt-out.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHART_DIR="$ROOT_DIR/agent-operator/chart"

render() {
  helm template gateway-route-check "$CHART_DIR" \
    --namespace severalnines-system \
    "$@"
}

# Prints the value line following the env var name, e.g. `value: "true"`.
route_env_value() {
  grep -A1 'name: PROMETHEUS_STACK_GRAFANA_GATEWAY_ROUTE' | grep 'value:' || true
}

# --- 1. defaults: env var present and true ----------------------------------
default_value="$(render | route_env_value)"
if [[ "$default_value" != *'"true"'* ]]; then
  echo "defaults must render PROMETHEUS_STACK_GRAFANA_GATEWAY_ROUTE=\"true\", got: ${default_value:-<absent>}" >&2
  exit 1
fi

# --- 2. opted out: env var present and false (never omitted) ----------------
optout_value="$(render --set prometheusStack.grafana.gatewayRoute=false | route_env_value)"
if [[ "$optout_value" != *'"false"'* ]]; then
  echo "gatewayRoute=false must render PROMETHEUS_STACK_GRAFANA_GATEWAY_ROUTE=\"false\", got: ${optout_value:-<absent>}" >&2
  exit 1
fi

echo "grafana_gateway_route.sh: OK"
