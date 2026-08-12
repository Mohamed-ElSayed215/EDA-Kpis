# argocd/infra — cluster-wide infrastructure

Contains ArgoCD Applications for tools that serve the **whole cluster**,
not any single application: External Secrets Operator, Vault.

## Why this is separate from `argocd/local.yaml` / `dev.yaml` / etc.

`helm/portal` is a namespace-scoped application chart. ESO and Vault are
cluster-scoped infrastructure that any number of unrelated applications
(not just `portal`) may depend on. Putting them as Helm `dependencies:`
inside `helm/portal/Chart.yaml` would mean:

- Every `helm upgrade` of `portal` re-evaluates ESO/Vault too — risking an
  unrelated restart of infra that other apps also rely on.
- Two different application charts both vendoring ESO as a dependency
  fight over ownership of the same cluster-scoped CRDs.
- Deleting the `portal` release would delete cluster infrastructure used
  by other teams/apps.

Keeping them as their own top-level ArgoCD Applications, synced from
`argocd/infra/`, keeps the infra lifecycle independent of any one
application's lifecycle — this is the standard "platform vs. application"
separation.

## One-time bootstrap (per cluster)

```bash
kubectl apply -f argocd/infra/root-infra.yaml
```

This is the only manifest you ever apply manually. It's an "app of apps"
— ArgoCD will then pick up `external-secrets.yaml` and `vault.yaml` (and
anything else later added to this directory) automatically.

```bash
kubectl get application -n argocd
# expect: infra-root, external-secrets, vault, plus portal-local/dev/stage/prod
```

## Ordering

`sync-wave: "-1"` on `external-secrets.yaml` and `vault.yaml` ensures
they sync before `sync-wave: "0"` application Applications (`portal-*`)
that depend on the ExternalSecret/SecretStore CRDs existing.

## Local dev note

`vault.yaml` runs Vault in **dev mode** (`server.dev.enabled: true`) —
in-memory, auto-unsealed, hardcoded root token `"root"`. This is fine for
a throwaway KinD cluster only. Do not reuse these values for stage/prod.
