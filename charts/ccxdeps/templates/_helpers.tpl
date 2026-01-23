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
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "ccx.acid-ccx.credentials.postgresql.acid.zalan.do") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- (get $secretData "username" | b64dec) | required "ccx db credentials secret username is missing" }}
{{- end }}

{{- define "ccx.db.password" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace "ccx.acid-ccx.credentials.postgresql.acid.zalan.do") | default dict }}
{{- $secretData := (get $secretObj "data") | default dict }}
{{- (get $secretData "password" | b64dec) | required "ccx db credentials secret password is missing" }}
{{- end }}

{{- define "ccx.sessionDomain" -}}
{{- .Values.sessionDomain | required "sessionDomain is required" }}
{{- end }}

{{- define "ccx.ccxFQDN" -}}
{{- .Values.ccxFQDN | required "ccxFQDN is required" }}
{{- end }}

{{- define "ccx.ccFQDN" -}}
{{- .Values.ccFQDN | default ( printf "cc.%s" ( include "ccx.ccxFQDN" . ) ) }}
{{- end }}

{{- define "ccx.cmonDbHost" -}}
{{- .Values.cmon.db.host | default "ccx-cmon-db-mysql-master" }}
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
{{- .Values.cmon.db.password | default "ccxRocks" }}
{{- end }}

{{- define "ccx.cmonRPCKey" -}}
{{- include "ccx.cmonPassword" . }}
{{- end }}

{{- define "loki.username" -}}
{{- .Values.loki.username | default "ccx" -}}
{{- end -}}

{{- define "loki.password" -}}
{{- .Values.loki.password | default (randAlphaNum 32) -}}
{{- end -}}