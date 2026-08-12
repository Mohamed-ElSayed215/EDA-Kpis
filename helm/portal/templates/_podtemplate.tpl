{{/*
==============================================================================
POD TEMPLATE SPEC
Renders the full `template:` block (metadata + spec) shared by every
workload kind (Deployment, StatefulSet, CronJob's jobTemplate, Job).
Keeping this in one place means adding a new workload kind later never
requires re-implementing containers/volumes/scheduling - only the
top-level controller wrapper (workload.yaml) differs.

ctx = dict "root" $ "svc" $svc "serviceName" $name
==============================================================================
*/}}
{{- define "portal.podTemplateSpec" -}}
metadata:
  labels:
{{ include "portal.podLabels" . | indent 4 }}
  {{- $checksums := include "portal.configChecksum" (dict "ctx" .) }}
  {{- if or .svc.podAnnotations $checksums }}
  annotations:
    {{- if .svc.podAnnotations }}
{{ toYaml .svc.podAnnotations | indent 4 }}
    {{- end }}
    {{- if $checksums }}
{{ $checksums | indent 4 }}
    {{- end }}
  {{- end }}
spec:
  serviceAccountName: {{ include "portal.serviceAccountName" . }}
  automountServiceAccountToken: {{ .svc.serviceAccount.automountServiceAccountToken | default false }}
  {{- if .svc.terminationGracePeriodSeconds }}
  terminationGracePeriodSeconds: {{ .svc.terminationGracePeriodSeconds }}
  {{- end }}
  {{- if .root.Values.global.imagePullSecrets }}
  imagePullSecrets:
{{ toYaml .root.Values.global.imagePullSecrets | indent 4 }}
  {{- end }}
  {{- if .svc.priorityClassName }}
  priorityClassName: {{ .svc.priorityClassName }}
  {{- end }}
  {{- if .svc.restartPolicy }}
  restartPolicy: {{ .svc.restartPolicy }}
  {{- end }}
{{ include "portal.podSecurityContext" . | indent 2 }}
  {{- if .svc.nodeSelector }}
  nodeSelector:
{{ toYaml .svc.nodeSelector | indent 4 }}
  {{- end }}
  {{- if .svc.tolerations }}
  tolerations:
{{ toYaml .svc.tolerations | indent 4 }}
  {{- end }}
{{ include "portal.affinity" . | indent 2 }}
{{ include "portal.topologySpreadConstraints" . | indent 2 }}
  {{- if .svc.initContainers }}
  initContainers:
{{ toYaml .svc.initContainers | indent 4 }}
  {{- end }}
  containers:
    - name: {{ .serviceName }}
      image: {{ include "portal.image" . }}
      imagePullPolicy: {{ .svc.image.pullPolicy | default "IfNotPresent" }}
{{ include "portal.containerSecurityContext" . | indent 6 }}
      {{- if .svc.containerPort }}
      ports:
        - name: http
          containerPort: {{ .svc.containerPort }}
          protocol: TCP
      {{- end }}
      {{- if .svc.command }}
      command:
{{ toYaml .svc.command | indent 8 }}
      {{- end }}
      {{- if .svc.args }}
      args:
{{ toYaml .svc.args | indent 8 }}
      {{- end }}
      {{- if or .svc.env .root.Values.global.env }}
      env:
{{ toYaml (.svc.env | default .root.Values.global.env) | indent 8 }}
      {{- end }}
      {{- if or .svc.envFrom .root.Values.global.envFrom }}
      envFrom:
{{ toYaml (.svc.envFrom | default .root.Values.global.envFrom) | indent 8 }}
      {{- end }}
{{ include "portal.resources" . | indent 6 }}
{{ include "portal.probe" (merge (dict "kind" "startupProbe") .) | indent 6 }}
{{ include "portal.probe" (merge (dict "kind" "readinessProbe") .) | indent 6 }}
{{ include "portal.probe" (merge (dict "kind" "livenessProbe") .) | indent 6 }}
      {{- if .svc.lifecycle }}
      {{- if or .svc.lifecycle.preStop .svc.lifecycle.postStart }}
      lifecycle:
        {{- if .svc.lifecycle.preStop }}
        preStop:
{{ toYaml .svc.lifecycle.preStop | indent 10 }}
        {{- end }}
        {{- if .svc.lifecycle.postStart }}
        postStart:
{{ toYaml .svc.lifecycle.postStart | indent 10 }}
        {{- end }}
      {{- end }}
      {{- end }}
      {{- if or .svc.volumeMounts .svc.configMap.enabled .svc.secret.enabled .svc.pvc.enabled }}
      volumeMounts:
        {{- if .svc.volumeMounts }}
{{ toYaml .svc.volumeMounts | indent 8 }}
        {{- end }}
        {{- if .svc.configMap.enabled }}
        - name: config
          mountPath: {{ .svc.configMap.mountPath | default "/etc/config" }}
        {{- end }}
        {{- if .svc.secret.enabled }}
        - name: secret
          mountPath: {{ .svc.secret.mountPath | default "/etc/secret" }}
        {{- end }}
      {{- end }}
    {{- if .svc.sidecars }}
{{ toYaml .svc.sidecars | indent 4 }}
    {{- end }}
  {{- if or .svc.volumes .svc.configMap.enabled .svc.secret.enabled }}
  volumes:
    {{- if .svc.volumes }}
{{ toYaml .svc.volumes | indent 4 }}
    {{- end }}
    {{- if .svc.configMap.enabled }}
    - name: config
      configMap:
        name: {{ .svc.configMap.nameOverride | default (include "portal.serviceFullname" (dict "root" .root "serviceName" .serviceName)) }}
    {{- end }}
    {{- if .svc.secret.enabled }}
    - name: secret
      secret:
        secretName: {{ .svc.secret.nameOverride | default (include "portal.serviceFullname" (dict "root" .root "serviceName" .serviceName)) }}
    {{- end }}
  {{- end }}
{{- end -}}
