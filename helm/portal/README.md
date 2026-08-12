# portal

A single, generic Helm chart that renders every service in the Portal
monorepo (frontend, backend, and any future service — worker, scheduler,
notification, websocket, api-gateway, migration-job, cronjob, ...) from
one set of templates.

**Adding a new service never requires a new template.** It requires only
a new entry under `services.<name>` in the appropriate values file.

## How it works

- `values.yaml` defines `global` (defaults) and `services` (a map of
  service name -> config). Every service inherits every field from
  `global` and may override any of it — see
  `templates/_helpers.tpl` (`portal.mergedService`).
- Each service declares a `type`: `deployment` | `statefulset` |
  `cronjob` | `job`. `templates/workload.yaml` branches on this field to
  render the correct controller kind. This is what lets one chart cover
  long-running services and one-shot/scheduled jobs without duplicating
  templates.
- Every optional resource (Ingress, HPA, KEDA ScaledObject, PDB,
  NetworkPolicy, ServiceMonitor, PodMonitor, PrometheusRule,
  ExternalSecret, RBAC, PVC, ...) is gated behind its own
  `<resource>.enabled` flag. Disabled = not rendered, not just empty.
- Environment differences live in `environments/<env>/values.yaml` and
  are layered on top of the chart's `values.yaml` via `-f` /
  `helm.valueFiles` (ArgoCD). Each environment file contains only the
  fields that differ from the chart defaults.

## Repository layout

```
helm/portal/            # this chart
environments/<env>/     # per-environment value overrides (local/dev/stage/prod)
argocd/<env>.yaml        # ArgoCD Application per environment
```

## Adding a new service

1. Add an entry under `services.<name>` in `helm/portal/values.yaml`
   with at least `enabled`, `type`, and `image.repository`.
2. Add any environment-specific overrides (replica count, image tag,
   ingress host, resource sizing) under
   `environments/<env>/values.yaml`.
3. Nothing under `templates/` changes.

## Values contract (high level)

| Field | Applies to | Notes |
|---|---|---|
| `type` | all | `deployment`, `statefulset`, `cronjob`, `job` — required |
| `enabled` | all | master on/off switch for the whole service |
| `image.repository` / `.tag` / `.pullPolicy` | all | required: `repository` |
| `replicaCount` | deployment/statefulset | ignored if `hpa.enabled` |
| `schedule` | cronjob | required when `type: cronjob` |
| `service.enabled` | deployment | renders a ClusterIP/NodePort/LoadBalancer Service |
| `ingress.enabled` | deployment | supports multiple hosts/paths/TLS |
| `hpa.enabled` / `keda.enabled` | deployment | mutually exclusive — KEDA manages its own HPA |
| `pdb.enabled` | deployment/statefulset | exactly one of `minAvailable`/`maxUnavailable` required |
| `configMap.enabled` / `secret.enabled` / `externalSecret.enabled` | all | pod restarts automatically on data change via checksum annotations |
| `rbac.enabled` / `clusterRbac.enabled` | all | Role+RoleBinding or ClusterRole+ClusterRoleBinding |

`values.schema.json` enforces the required/typed fields above at
`helm template`/`helm install` time; everything else is intentionally
left permissive so the chart doesn't need a schema change for every new
optional field.

## Validating changes

```bash
# Lint the chart itself
helm lint helm/portal

# Render each environment and eyeball the diff
helm template portal-local helm/portal -f environments/local/values.yaml
helm template portal-dev   helm/portal -f environments/dev/values.yaml
helm template portal-stage helm/portal -f environments/stage/values.yaml
helm template portal-prod  helm/portal -f environments/prod/values.yaml

# Validate rendered manifests against the Kubernetes API (server-side
# dry-run catches things `helm lint` can't, e.g. invalid field values)
helm template portal-prod helm/portal -f environments/prod/values.yaml \
  | kubectl apply --dry-run=server -f -

# Schema validation happens automatically as part of `helm template`/
# `helm install` — Helm loads values.schema.json if present.
```

Recommended CI gate: run all four `helm template` commands above plus
`helm lint --strict` on every PR that touches `helm/portal/**` or
`environments/**`.

## Known intentional limitations

- `lookup` is not used anywhere in this chart. It behaves inconsistently
  under ArgoCD's manifest generation (no guaranteed live-cluster context)
  and would break reproducible, diffable GitOps renders.
- Plain `Secret` resources are meant for local/dev convenience only.
  Production defaults to `externalSecret.enabled: true` — do not put real
  secret values in `environments/prod/values.yaml`.
- StatefulSet volume claims use native `volumeClaimTemplates`; standalone
  `PersistentVolumeClaim` (`templates/pvc.yaml`) is for Deployment/Job/
  CronJob workloads that need a pre-existing claim (e.g. shared RWX
  volume) — you still need to reference it manually under
  `volumes`/`volumeMounts` for those workload types.
