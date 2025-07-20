{{/*
Expand the name of the chart.
*/}}
{{- define "linkwarden.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "linkwarden.fullname" -}}
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
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "linkwarden.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "linkwarden.labels" -}}
helm.sh/chart: {{ include "linkwarden.chart" . }}
{{ include "linkwarden.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "linkwarden.selectorLabels" -}}
app.kubernetes.io/name: {{ include "linkwarden.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "linkwarden.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "linkwarden.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Set the names for the ConfigMaps
*/}}
{{- define "linkwarden.configmaps.general" }}
{{- printf "%s-general" (include "linkwarden.fullname" .) }}
{{- end }}

{{- define "linkwarden.configmaps.auth" }}
{{- printf "%s-auth" (include "linkwarden.fullname" .) }}
{{- end }}

{{/*
Set the names of the secrets
*/}}
{{- define "linkwarden.secrets.nextAuth" -}}
{{- printf "%s-next-auth" (include "linkwarden.fullname" .) }}
{{- end }}

{{- define "linkwarden.secrets.s3" -}}
{{- printf "%s-s3" (include "linkwarden.fullname" .) }}
{{- end }}

{{- define "linkwarden.secrets.db" -}}
{{- printf "%s-db" (include "linkwarden.fullname" .) }}
{{- end }}

{{/*
Define the PV name
*/}}
{{- define "linkwarden.pv.name" -}}
{{- printf "%s-pv" (include "linkwarden.fullname" .)}}
{{- end -}}

{{/*
Define the PVC name
*/}}
{{- define "linkwarden.pvc.name" -}}
{{- printf "%s-pvc" (include "linkwarden.fullname" .)}}
{{- end -}}

{{/*
Obtain the API version for the Pod Disruption Budget
*/}}
{{- define "linkwarden.pdb.apiVersion" -}}
{{- if and (.Capabilities.APIVersions.Has "policy/v1") (semverCompare ">= 1.21-0" .Capabilities.KubeVersion.Version) -}}
{{- print "policy/v1" }}
{{- else -}}
{{- print "policy/v1beta1" }}
{{- end -}}
{{- end -}}


{{/*
Define the absolute data path
*/}}
{{- define "linkwarden.paths.data" -}}
{{- printf "/data/%s" .Values.linkwarden.data.filesystem.dataPath }}
{{- end -}}
