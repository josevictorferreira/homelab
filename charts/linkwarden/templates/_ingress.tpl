{{- define "linkwarden.ingress.scheme" }}
{{- if gt (len .Values.ingress.tls) 0 -}}
{{- print "https" }}
{{- else -}}
{{- print "http" }}
{{- end -}}
{{- end }}

{{- define "linkwarden.ingress.url" -}}
{{ printf "%s://%s/api/v1/auth" (include "linkwarden.ingress.scheme" .) .Values.linkwarden.domain }}
{{- end }}
