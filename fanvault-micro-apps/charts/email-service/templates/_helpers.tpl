{{/*
  Standard labels for all microservice resources.
  Call: include "microapp.labels" .
*/}}
{{- define "microapp.labels" -}}
app.kubernetes.io/name: {{ include "microapp.name" . }}
app.kubernetes.io/component: {{ .Values.component | default "backend" }}
app.kubernetes.io/part-of: {{ .Values.partOf | default "fanvault" }}
app.kubernetes.io/version: {{ .Values.image.tag | default "latest" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
role: {{ .Values.role | default "dev-backend" }}
{{- end }}

{{/*
  Selector labels — MUST be stable (not change across upgrades).
  Only name + part-of; do NOT include version here.
*/}}
{{- define "microapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microapp.name" . }}
{{- end }}

{{/*
  Service name — uses nameOverride if set, else chart name.
*/}}
{{- define "microapp.name" -}}
{{- .Values.nameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
  Namespace — uses .Values.namespace if set, else "dev"
*/}}
{{- define "microapp.namespace" -}}
{{- .Values.namespace | default "dev" }}
{{- end }}
