{{/*
Expand the name of the chart.
*/}}
{{- define "ccx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ccx.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ccx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}{{/*
Common labels
*/}}
{{- define "ccx.labels" -}}
helm.sh/chart: {{ include "ccx.chart" . }}
{{ include "ccx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}{{/*
Selector labels
*/}}
{{- define "ccx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ccx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}{{/*
Create the name of the service account to use
*/}}
{{- define "ccx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ccx.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

# retrieve the secret data using lookup function and when not exists, return an empty dictionary / map as result
# set $cmonPassword to existing secret data or generate a random one when not exists
{{- define "ccx.cmonPassword" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "cmon-credentials") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- or (get $secretData "cmon-password" | b64dec) .Values.cmon.password | default "8fcf2304e46f39fa70710583a41455fd39cc5408" }}
{{- end }}

{{- define "ccx.cmonUser" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "cmon-credentials") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- or (get $secretData "cmon-user" | b64dec) .Values.cmon.user | default "cmon-user" }}
{{- end }}

{{- define "ccx.db.username" -}}
{{- if .Values.ccx.db.username }}
{{- .Values.ccx.db.username }}
{{- else }}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "ccx.acid-ccx.credentials.postgresql.acid.zalan.do") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- (get $secretData "username" | b64dec) | required "ccx db credentials secret username is missing" }}
{{- end }}
{{- end }}

{{- define "ccx.db.password" -}}
{{- if .Values.ccx.db.password }}
{{- .Values.ccx.db.password }}
{{- else }}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "ccx.acid-ccx.credentials.postgresql.acid.zalan.do") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- (get $secretData "password" | b64dec) | required "ccx db credentials secret password is missing" }}
{{- end }}
{{- end }}

{{- define "ccx.db.address" -}}
{{- .Values.ccx.db.address | required "ccx.db.address is required" }}
{{- end }}

{{- define "ccx.db.port" -}}
{{- .Values.ccx.db.port | required "ccx.db.port is required" }}
{{- end }}

{{- define "ccx.ccxFQDN" -}}
{{- .Values.ccxFQDN | required "ccxFQDN is required" }}
{{- end }}

{{- define "ccx.ccFQDN" -}}
{{- .Values.ccFQDN | default ( printf "cc.%s" ( include "ccx.ccxFQDN" . ) ) }}
{{- end }}

{{- define "ccx.cmonDbHost" -}}
{{- .Values.cmon.db.host | default "ccxdeps" }}
{{- end }}

{{- define "ccx.cmonDbPort" -}}
{{- .Values.cmon.db.port | default 3306 }}
{{- end }}

{{- define "ccx.cmonDbName" -}}
{{- .Values.cmon.db.name | default "cmon" }}
{{- end }}

{{- define "ccx.cmonDbUser" -}}
{{- .Values.cmon.db.user | default "cmon" }}
{{- end }}

{{- define "ccx.cmonDbPassword" -}}
{{- .Values.cmon.db.password | default "Super$3cr3t" }}
{{- end }}

{{- define "ccx.cmonRPCKey" -}}
{{- include "ccx.cmonPassword" . }}
{{- end }}

{{- define "ccx.prometheusHostname" -}}
{{- if not .Values.prometheusHostname }}
{{- $serviceObj := (lookup "v1" "Service" .Release.Namespace "victoria-metrics") }}
{{- if not $serviceObj }}
{{- fail ".Values.prometheusHostname is required when not using embedded monitoring stack!" }}
{{- else }}
{{- "victoria-metrics" }}
{{- end }}
{{- else }}
{{- .Values.prometheusHostname }}
{{- end }}
{{- end }}

{{- define "ccx.prometheusSelectorName" -}}
{{- if .Values.prometheusSelectorName }}
{{- .Values.prometheusSelectorName | trim -}}
{{- else if .Values.prometheusHostname }}
{{- .Values.prometheusHostname | trim -}}
{{- else }}
{{- $serviceObj := (lookup "v1" "Service" .Release.Namespace "victoria-metrics") }}
{{- if not $serviceObj }}
{{- fail ".Values.prometheusHostname is required when not using embedded monitoring stack!" }}
{{- else }}
{{- "victoria-metrics" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "ccx.checkFluentBitConfig" -}}
{{- if and .Values.fluentbit.enabled (not .Values.fluentbit.hostSet) }}
  {{- if not .Values.fluentbit.host }}
    {{- $_ := set .Values.fluentbit "host" (printf "%s" (include "ccx.ccxFQDN" .)) }}
    {{- $_ := set .Values.fluentbit "hostSet" true }}
  {{- else if ne .Values.fluentbit.host "loki.local" }}
    {{- $_ := set .Values.fluentbit "hostSet" true }}
  {{- else }}
    {{- $_ := set .Values.fluentbit "host" (printf "%s" (include "ccx.ccxFQDN" .)) }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "ccx.KeycloakService" -}}
{{- $keycloak := (lookup "v1" "Service" .Release.Namespace "keycloak") }}
{{- if $keycloak }}
{{- "keycloak" }}
{{- else -}}
{{- $keycloak := (lookup "v1" "Service" .Release.Namespace "ccxdeps-keycloak") }}
{{- if $keycloak }}
{{- "ccxdeps-keycloak" }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "ccx.services.admin.basicauth.username" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "admin-basic-auth") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- or (get $secretData "ADMIN_AUTH_USERNAME" | b64dec) .Values.ccx.services.admin.basicauth.username | default "admin" }}
{{- end -}}

{{- define "ccx.services.admin.basicauth.password" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "admin-basic-auth") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- or (get $secretData "ADMIN_AUTH_PASSWORD" | b64dec) .Values.ccx.services.admin.basicauth.password | default (randAlphaNum 16) }}
{{- end -}}

{{- define "ccx.admin.email" -}}
{{- .Values.ccx.admin.email | default "admin@getccx.com" }}
{{- end -}}

{{- define "ccx.admin.password" -}}
{{- .Values.ccx.admin.password | default (randAlphaNum 16) }}
{{- end -}}

{{- define "ccx.admin.users" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "admin-users") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- or (get $secretData "ADMIN_USERS" | b64dec) (printf "%s:%s" (include "ccx.admin.email" .) (include "ccx.admin.password" .)) }}
{{- end -}}

{{- define "ccx.cidr" -}}
{{ $cidrList := list }}
{{- if .Values.ccx.cidr }}
{{ $cidrList = append $cidrList .Values.ccx.cidr }}
{{- else }}
{{- $nodes := lookup "v1" "Node" "" "" -}}
{{- $found := false -}}
{{- if $nodes.items -}}
{{- range $node := $nodes.items }}
  {{- $addresses := $node.status.addresses -}}
  {{- range $address := $addresses }}
    {{- if eq $address.type "ExternalIP" }}
      {{- $found = true -}}
      {{ $cidrList = append $cidrList (printf "%s/32" $address.address) }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- if not $found }}
{{ $cidrList = append $cidrList "0.0.0.0/0" }}
{{- end }}
{{- end }}
{{ toJson $cidrList }}
{{- end }}

{{- define "ccx.checkSecrets" -}}
{{- $cloudSecrets := .Values.ccx.cloudSecrets -}}
{{- $allSecretsExist := true -}}
{{- if $cloudSecrets }}
  {{- range $secret := $cloudSecrets }}
    {{- $lookupResult := lookup "v1" "Secret" $.Release.Namespace $secret -}}
    {{- if not $lookupResult }}
      {{- $allSecretsExist = false -}}
      {{- fail (printf "Missing secret defined in .Values.ccx.cloudSecrets - %s" $secret ) }}
    {{- end }}
  {{- end }}
{{- else }}
  {{- fail "No secrets defined in .Values.ccx.cloudSecrets" }}
{{- end }}
{{- $allSecretsExist -}}
{{- end }}

# CMON helpers

{{- define "cmon.initContainer.migrateToK8s" -}}
- name: migrate-file-to-k8s-secrets
  image: {{ .Values.cmon.image | required ".Values.cmon.image is missing" }}
  {{- if .Values.cmon.coreDumpEnable }}
  securityContext:
    privileged: true
  {{- end }}
  command: [ "/bin/sh", "-c" ]
  args:
    - cp /tmp/cmon.cnf /etc/cmon.cnf;
      /usr/bin/check-cmon.sh;
      echo "Starting configuration upgrade";
      /usr/sbin/cmon --k8s --migrate-secrets --debug --nodaemon;
      echo "Finishing configuration upgrade";
  {{- if .Values.cmon.coreDumpEnable }}
      sysctl -w kernel.core_pattern=/etc/cmon.d/core.%h.%e.%p.%t;
  {{- end }}
  volumeMounts:
    - mountPath: /tmp/cmon.cnf
      subPath: cmon.cnf
      name: cmon-cnf-cfg
    - mountPath: /etc/cmon.d/
      name: cmon-master-pv
    - mountPath: /var/lib/cmon
      name: cmon-pv-var-lib-cmon
{{- end }}

{{- define "cmon.initContainer.restoreFromK8s" -}}
- name: restore-file-from-k8s-secrets
  image: {{ .Values.cmon.restoreImage | default "alpine/k8s:1.30.0" }}
  volumeMounts:
    - mountPath: /etc/cmon.d
      name: cmon-master-pv
    - mountPath: /var/lib/cmon
      name: cmon-pv-var-lib-cmon
  command:
    - bash
    - -c
    - |
      set -euo pipefail
      log() { echo "[$(date '+%H:%M:%S')] $*"; }

      has_data=$(ls /var/lib/cmon/cmon.data /etc/cmon.d/cmon_*.cnf 2>/dev/null | head -1 || true)
      if [ -n "$has_data" ]; then
          log "PVCs already populated — skipping restore"
          exit 0
      fi

      SECRET_PREFIX="com.severalnines.cmon."
      DATA_KEY="content"
      SKIP_SECRETS=("com.severalnines.cmon.etc.cmon.cnf")

      secret_to_path() {
          local secret="$1"
          local rest="${secret#${SECRET_PREFIX}}"
          [[ "$rest" == "$secret" ]] && return 0
          case "$rest" in
              etc.cmon.cnf) echo "/etc/cmon.cnf" ;;
              var.lib.cmon.cloud-credentials.json) echo "/var/lib/cmon/cloud_credentials.json" ;;
              var.lib.cmon.cmon.data) echo "/var/lib/cmon/cmon.data" ;;
              var.lib.cmon.ca.cmon.rpc-tls.crt) echo "/var/lib/cmon/ca/cmon/rpc_tls.crt" ;;
              var.lib.cmon.ca.cmon.rpc-tls.key) echo "/var/lib/cmon/ca/cmon/rpc_tls.key" ;;
              etc.cmon.d.cmon-*.cnf)
                  local cid="${rest#etc.cmon.d.cmon-}"; cid="${cid%.cnf}"
                  [[ "$cid" =~ ^[0-9]+$ ]] && echo "/etc/cmon.d/cmon_${cid}.cnf" ;;
              var.lib.cmon.ca.*.cluster-*)
                  local tail="${rest#var.lib.cmon.ca.}"
                  local type_part="${tail%%.cluster-*}"
                  local after="${tail#${type_part}.cluster-}"
                  local cid="${after%%.*}"
                  local fname="${after#${cid}.}"
                  if [[ "$cid" =~ ^[0-9]+$ && -n "$type_part" && -n "$fname" && "$fname" != "$after" ]]; then
                      type_part="${type_part//-/_}"
                      fname="${fname//-/_}"
                      echo "/var/lib/cmon/ca/${type_part}/cluster_${cid}/${fname}"
                  fi ;;
          esac
      }

      mode_for_path() {
          case "$1" in
              *.key|*/cmon.data|*/cloud_credentials.json|/etc/cmon.cnf|/etc/cmon.d/*.cnf) echo "600" ;;
              *) echo "644" ;;
          esac
      }

      mapfile -t SECRETS < <(
          kubectl get secrets -o custom-columns=NAME:.metadata.name --no-headers \
              | grep "^com\.severalnines\.cmon\." \
              | grep -v '\.backup$' \
              | grep -v '^removed\.' \
              || true
      )
      log "Found ${#SECRETS[@]} candidate secret(s)"

      restored=0; failures=0
      for secret in "${SECRETS[@]}"; do
          [[ -z "$secret" ]] && continue
          skip=0
          for s in "${SKIP_SECRETS[@]}"; do
              [[ "$secret" == "$s" ]] && { skip=1; break; }
          done
          [[ "$skip" == "1" ]] && continue

          path=$(secret_to_path "$secret") || true
          [[ -z "$path" ]] && continue

          b64=$(kubectl get secret "$secret" -o "jsonpath={.data.${DATA_KEY}}" 2>/dev/null || true)
          if [[ -z "$b64" ]]; then
              log "WARN: no data in $secret"
              failures=$((failures+1)); continue
          fi

          mkdir -p "$(dirname "$path")"
          printf '%s' "$b64" | base64 -d > "$path"
          chmod "$(mode_for_path "$path")" "$path"
          log "restored: $secret -> $path"
          restored=$((restored+1))
      done

      log "Done. Restored: $restored, failures: $failures"
      exit $(( failures > 0 ? 1 : 0 ))
{{- end }}
