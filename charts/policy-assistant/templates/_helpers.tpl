{{- define "pa.name" -}}policy-assistant{{- end -}}

{{- define "pa.labels" -}}
app.kubernetes.io/name: {{ include "pa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "pa.selector" -}}
app.kubernetes.io/name: {{ include "pa.name" . }}
{{- end -}}
