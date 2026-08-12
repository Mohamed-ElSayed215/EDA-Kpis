{{/*
==============================================================================
NAMING
==============================================================================
*/}}

{{- define "eda-kpis.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified name for a specific service: <release>-<service>.
Truncated to 63 chars (DNS label limit) - this is why we don't simply
concatenate release+chart+service unconditionally.
*/}}
{{- define "eda-kpis.serviceFullname" -}}
{{- printf "%s-%s" .root.Release.Name .serviceName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "eda-kpis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
==============================================================================
VALUES MERGE - global -> service inheritance
==============================================================================
Every service inherits every field from `.Values.global` and may override
any of it. We deep-copy global (so we never mutate the real values tree)
and deep-merge the service's own values on top, with the service winning
on any key present in both. Callers get the merged result back as a dict
by capturing this template's YAML output with `fromYaml`:

    {{- $svc := include "eda-kpis.mergedService" (dict "root" $ "serviceName" $name) | fromYaml -}}

This is the ONLY place inheritance logic lives - every resource template
uses $svc afterwards and never reads .Values.global or .Values.services
directly, which keeps the "inherit + override" rule enforced in one spot.
*/}}
{{- define "eda-kpis.mergedService" -}}
{{- $global := .root.Values.global | default dict -}}
{{- $service := index .root.Values.services .serviceName | default dict -}}
{{- $merged := mustMergeOverwrite (deepCopy $global) $service -}}
{{- $merged = merge $merged (dict "name" .serviceName) -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
==============================================================================
LABELS
==============================================================================
Kubernetes recommended labels (app.kubernetes.io/*) plus our own chart
label. `ctx` = dict "root" $ "svc" $svc "serviceName" $name
*/}}
{{- define "eda-kpis.labels" -}}
helm.sh/chart: {{ include "eda-kpis.chart" .root }}
{{ include "eda-kpis.selectorLabels" . }}
app.kubernetes.io/version: {{ .svc.image.tag | default .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: {{ .root.Values.global.partOf | default .root.Chart.Name }}
{{- if .svc.labels }}
{{ toYaml .svc.labels }}
{{- end }}
{{- end -}}

{{- define "eda-kpis.selectorLabels" -}}
app.kubernetes.io/name: {{ .serviceName }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .svc.component | default .serviceName }}
{{- end -}}

{{- define "eda-kpis.podLabels" -}}
{{ include "eda-kpis.selectorLabels" . }}
{{- if .svc.podLabels }}
{{ toYaml .svc.podLabels }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
SERVICE ACCOUNT NAME
==============================================================================
*/}}
{{- define "eda-kpis.serviceAccountName" -}}
{{- if .svc.serviceAccount.enabled -}}
{{- .svc.serviceAccount.name | default (include "eda-kpis.serviceFullname" (dict "root" .root "serviceName" .serviceName)) -}}
{{- else -}}
{{- .svc.serviceAccount.name | default "default" -}}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
IMAGE
==============================================================================
*/}}
{{- define "eda-kpis.image" -}}
{{- $tag := .svc.image.tag | default .root.Chart.AppVersion -}}
{{- printf "%s:%s" .svc.image.repository $tag -}}
{{- end -}}

{{/*
==============================================================================
SECURITY CONTEXTS
Rendered only if the caller has a non-empty dict - each field is still
individually overridable because we just toYaml whatever was merged in.
==============================================================================
*/}}
{{- define "eda-kpis.podSecurityContext" -}}
{{- if .svc.podSecurityContext }}
securityContext:
{{ toYaml .svc.podSecurityContext | indent 2 }}
{{- end }}
{{- end -}}

{{- define "eda-kpis.containerSecurityContext" -}}
{{- if .svc.containerSecurityContext }}
securityContext:
{{ toYaml .svc.containerSecurityContext | indent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
RESOURCES
==============================================================================
*/}}
{{- define "eda-kpis.resources" -}}
{{- if .svc.resources }}
resources:
{{ toYaml .svc.resources | indent 2 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
PROBES
`kind` = "startupProbe" | "readinessProbe" | "livenessProbe"
Supports httpGet, tcpSocket, exec - whichever block the user populates
under .svc.<kind>.httpGet / .tcpSocket / .exec is rendered verbatim, the
rest (thresholds, periods) is common.
==============================================================================
*/}}
{{- define "eda-kpis.probe" -}}
{{- $probe := index .svc .kind -}}
{{- if $probe.enabled }}
{{ .kind }}:
{{- if $probe.httpGet }}
  httpGet:
{{ toYaml $probe.httpGet | indent 4 }}
{{- else if $probe.tcpSocket }}
  tcpSocket:
{{ toYaml $probe.tcpSocket | indent 4 }}
{{- else if $probe.exec }}
  exec:
{{ toYaml $probe.exec | indent 4 }}
{{- end }}
  initialDelaySeconds: {{ $probe.initialDelaySeconds | default 0 }}
  periodSeconds: {{ $probe.periodSeconds | default 10 }}
  timeoutSeconds: {{ $probe.timeoutSeconds | default 1 }}
  successThreshold: {{ $probe.successThreshold | default 1 }}
  failureThreshold: {{ $probe.failureThreshold | default 3 }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
AFFINITY / TOPOLOGY / SCHEDULING
==============================================================================
*/}}
{{- define "eda-kpis.affinity" -}}
{{- $svc := .svc -}}
{{- if or $svc.nodeAffinity ($svc.podAntiAffinity | default dict).enabled }}
affinity:
{{- if $svc.nodeAffinity }}
  nodeAffinity:
{{ toYaml $svc.nodeAffinity | indent 4 }}
{{- end }}
{{- if $svc.podAntiAffinity.enabled }}
  podAntiAffinity:
    {{- $type := $svc.podAntiAffinity.type | default "preferred" }}
    {{- if eq $type "required" }}
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: {{ $svc.podAntiAffinity.topologyKey | default "kubernetes.io/hostname" }}
        labelSelector:
          matchLabels:
{{ include "eda-kpis.selectorLabels" . | indent 12 }}
    {{- else }}
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: {{ $svc.podAntiAffinity.weight | default 100 }}
        podAffinityTerm:
          topologyKey: {{ $svc.podAntiAffinity.topologyKey | default "kubernetes.io/hostname" }}
          labelSelector:
            matchLabels:
{{ include "eda-kpis.selectorLabels" . | indent 14 }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "eda-kpis.topologySpreadConstraints" -}}
{{- if .svc.topologySpreadConstraints }}
topologySpreadConstraints:
{{- range .svc.topologySpreadConstraints }}
  - maxSkew: {{ .maxSkew | default 1 }}
    topologyKey: {{ .topologyKey }}
    whenUnsatisfiable: {{ .whenUnsatisfiable | default "ScheduleAnyway" }}
    labelSelector:
      matchLabels:
{{ include "eda-kpis.selectorLabels" $ | indent 8 }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
CONFIG/SECRET CHECKSUM ANNOTATIONS
Forces a pod restart when the rendered ConfigMap/Secret content changes,
even though the object name doesn't change (we do NOT use the
"immutable ConfigMap + hash suffix in name" pattern here, to keep
ExternalSecret/ConfigMap names stable and predictable for GitOps diffing).
==============================================================================
*/}}
{{- define "eda-kpis.configChecksum" -}}
{{- $ctx := .ctx -}}
{{- if $ctx.svc.configMap.enabled }}
checksum/configmap: {{ include "eda-kpis.configmapData" $ctx | sha256sum }}
{{- end }}
{{- if $ctx.svc.secret.enabled }}
checksum/secret: {{ include "eda-kpis.secretData" $ctx | sha256sum }}
{{- end }}
{{- end -}}

{{- define "eda-kpis.configmapData" -}}
{{- toYaml (.svc.configMap.data | default dict) }}
{{- toYaml (.svc.configMap.binaryData | default dict) }}
{{- end -}}

{{- define "eda-kpis.secretData" -}}
{{- toYaml (.svc.secret.data | default dict) }}
{{- toYaml (.svc.secret.stringData | default dict) }}
{{- end -}}
