{{- define "events.labels" -}}
app.kubernetes.io/part-of: events-project
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
tn.fst/feature: {{ .Values.feature | quote }}
tn.fst/owner: {{ .Values.owner | quote }}
{{- end }}

{{- define "events.appSelector" -}}
app.kubernetes.io/name: events-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "events.mysqlSelector" -}}
app.kubernetes.io/name: mysql
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
