#!/bin/sh
# Render checks for the cmon RPC v2 port (cc.cmonRpcPort): which port the probes,
# s9s.conf, ccmgradm --cmon-url and the Services use for a given cmon image.
# Needs helm and the chart dependencies (runs `helm dependency build` if missing).
# Usage: charts/clustercontrol/tests/rpc-port-render.sh
set -eu

CHART=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$CHART/charts" ] || helm dependency build "$CHART" >/dev/null

fail=0
render() {
  # cmon.license enables the license startupProbe.
  helm template t "$CHART" --set installMysqlOperator=false --set createDatabases=false \
    --set cmon.license=dGVzdA== "$@"
}

# check <expected port> <description> [helm args...]
check() {
  want=$1; desc=$2; shift 2
  out=$(render "$@") || { echo "FAIL $desc: helm template failed"; fail=1; return; }
  errs=""
  echo "$out" | grep -q -- "--cmon-url cmon-master:$want " || errs="$errs ccmgradm-cmon-url"
  echo "$out" | grep -q "s9s --controller=https://localhost:$want tree" || errs="$errs startupProbe"
  echo "$out" | grep -A3 'path: /v2/controller?operation=ping' | grep -q "port: $want$" || errs="$errs livenessProbe"
  echo "$out" | grep -q "controller=https://cmon-master:$want/" || errs="$errs s9s.conf"
  # cmon-master Service: 9500 and 9501 always present, both routed to $want.
  svc=$(echo "$out" | awk '/^kind: Service/{s=1} /^---/{s=0} s' | awk '/name: cmon-master$/{f=1} f' | sed -n '/ports:/,/selector:/p')
  for p in 9500 9501; do
    echo "$svc" | grep -A2 -- "- port: $p$" | grep -q "targetPort: $want$" || errs="$errs svc-$p"
  done
  if [ -n "$errs" ]; then echo "FAIL $desc (want $want):$errs"; fail=1; else echo "ok   $desc -> $want"; fi
}

img() { echo "--set cmon.image=$1"; }

# shellcheck disable=SC2046
{
check 9501 "default values (2.5.0-24068)"
check 9501 "2.5.0 tag"                   $(img severalnines/cmon:2.5.0-24068)
check 9501 "2.5.1 tag below cutoff"      $(img severalnines/cmon:2.5.1-25003)
check 9501 "latest"                      $(img severalnines/cmon:latest)
check 9501 "untagged"                    $(img severalnines/cmon)
check 9501 "untagged, registry with port" $(img registry.local:5000/severalnines/cmon)
check 9501 "tag@digest below cutoff"     $(img severalnines/cmon:2.5.0-24068@sha256:a5be9f101caf9000000000000000000000000000000000000000000000000000)
check 9501 "digest only"                 $(img severalnines/cmon@sha256:a5be9f101caf9000000000000000000000000000000000000000000000000000)
check 9501 "dev tag"                     $(img severalnines/cmon:2.5.1-25003-dev)
check 9501 "branch tag"                  $(img severalnines/cmon:CLUS-9165)
check 9500 "2.6.0 tag"                   $(img severalnines/cmon:2.6.0-27000)
check 9500 "tag@digest above cutoff"     $(img severalnines/cmon:2.6.0-27000@sha256:a5be9f101caf9000000000000000000000000000000000000000000000000000)
check 9500 "2.5.1 tag at lowered cutoff" $(img severalnines/cmon:2.5.1-25500) --set cmon.rpcPortCutoff=2.5.1-25500
check 9501 "2.5.1 tag below lowered cutoff" $(img severalnines/cmon:2.5.1-25499) --set cmon.rpcPortCutoff=2.5.1-25500
check 9500 "rpcPort override"            $(img severalnines/cmon:latest) --set cmon.rpcPort=9500
check 9501 "devBuild uses devImage"      --set devBuild=true $(img severalnines/cmon:2.6.0-27000) --set cmon.devImage=severalnines/cmon:latest
}

# A non-standard rpcPort gets its own Service port as well.
out=$(render --set cmon.rpcPort=9600)
echo "$out" | grep -q "name: 9600-port" && echo "ok   rpcPort=9600 -> own Service port" \
  || { echo "FAIL rpcPort=9600: no 9600-port on the Service"; fail=1; }

# publicService.ports.cmon targets the RPC port.
out=$(render $(img severalnines/cmon:2.6.0-27000) --set publicService.ports.cmon=9500)
echo "$out" | grep -A2 "name: cmon-rpc" | grep -q "targetPort: 9500" && echo "ok   publicService cmon-rpc -> 9500" \
  || { echo "FAIL publicService.ports.cmon: cmon-rpc does not target 9500"; fail=1; }

exit $fail
