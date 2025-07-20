{{/*
  Check whether a domain is given if the Ingress is enabled
*/}}
{{- define "linkwarden.checks.domain" -}}
  {{- if .Values.ingress.enabled }}
  {{- if not .Values.linkwarden.domain }}
  {{- fail "You did not provide domain name for the installation but enabled the Ingress. Please set '.Values.linkwarden.domain' also." }}
  {{- end }}
  {{- end }}
{{- end -}}

{{/*
  Check whether the given SSO providers are allowed - if any are actually provided
*/}}
{{- define "linkwarden.checks.providers" -}}
{{- $allowedList := include "linkwarden.auth.providers.withIssuers" . | fromJsonArray }}
{{- $authSSOLength := len .Values.linkwarden.auth.sso }}
  {{- if (gt $authSSOLength 0) }}
  {{- range $_, $v := .Values.linkwarden.auth.sso }}
  {{- if not (has $v.provider $allowedList) }}
  {{ fail "Your given SSO provider is not allowed. Please see 'values.yaml' comments for a list of allowed providers." }}
  {{- end }}
  {{- end }}
  {{- end }}
{{- end -}}
