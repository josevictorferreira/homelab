{{/*
Expand the name of the chart.
*/}}
{{- define "ntfy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ntfy.fullname" -}}
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
{{- define "ntfy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Build the Docker Hub image reference as used within the main and init-containers.
*/}}
{{- define "ntfy.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}{{- if .Values.image.digest }}@{{ .Values.image.digest }}{{ end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ntfy.labels" -}}
helm.sh/chart: {{ include "ntfy.chart" . }}
{{ include "ntfy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ntfy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ntfy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ntfy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ntfy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define the PV name
*/}}
{{- define "ntfy.pv" -}}
{{- printf "%s-pv" (include "ntfy.fullname" .)}}
{{- end -}}

{{/*
Define the PVC name
*/}}
{{- define "ntfy.pvc" -}}
{{- printf "%s-pvc" (include "ntfy.fullname" .)}}
{{- end -}}

{{/*
Define the Secret names
*/}}
{{- define "ntfy.secrets.smtp" -}}
{{- printf "%s-smtp" (include "ntfy.fullname" .)}}
{{- end -}}

{{- define "ntfy.secrets.web" -}}
{{- printf "%s-web" (include "ntfy.fullname" .)}}
{{- end -}}

{{- define "ntfy.secrets.twilio" -}}
{{- printf "%s-twilio" (include "ntfy.fullname" .)}}
{{- end -}}

{{- define "ntfy.secrets.upstream" -}}
{{- printf "%s-upstream" (include "ntfy.fullname" .)}}
{{- end -}}

{{/*
Obtain the API version for the Pod Disruption Budget
*/}}
{{- define "ntfy.pdb.apiVersion" -}}
{{- if and (.Capabilities.APIVersions.Has "policy/v1") (semverCompare ">= 1.21-0" .Capabilities.KubeVersion.Version) -}}
{{- print "policy/v1" }}
{{- else -}}
{{- print "policy/v1beta1" }}
{{- end -}}
{{- end -}}
