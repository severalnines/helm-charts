# ClusterControl Kubernetes Agent Operator


This Helm chart deploys the ClusterControl Kubernetes Agent Operator, which manages the lifecycle of database resources in a Kubernetes cluster.


## Installing the Chart

### From Git Repository

You can install the chart directly from the Git repository:

```bash
helm install kuber-agent kuber-agent --repo https://severalnines.github.io/helm-charts/ \
  --create-namespace \
  --namespace severalnines-system \
  --set agent.publicKey="<public-key>" \
  --set proxy.grpcAddress="host.docker.internal:50051" \
```

## Values

| Parameter                                 | Description                                                                                                         | Default                                                                |
|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| `image.repository`                        | Operator image repository                                                                                           | `europe-docker.pkg.dev/severalnines-public/clustercontrol/kuber-agent` |
| `image.tag`                               | Operator image tag                                                                                                  | `""` (defaults to chart appVersion)                                    |
| `image.pullPolicy`                        | Image pull policy                                                                                                   | `Always`                                                               |
| `agent.publicKey`                         | Public key for agent authentication                                                                                 | `""`                                                                   |
| `agent.name`                              | Name for the agent (if not set, uses the first node name in the cluster)                                            | `""`                                                                   |
| `namespaceOverride`                       | Override the namespace for resources                                                                                | `""`                                                                   |
| `createNamespace`                         | Create the namespace                                                                                                | `true`                                                                 |
| `controllerManager.replicas`              | Number of operator replicas                                                                                         | `1`                                                                    |
| `rbac.create`                             | Create RBAC resources                                                                                               | `true`                                                                 |
| `rbac.serviceAccounts.agent.name`         | Default ServiceAccount name used by the operator                                                                    | `agent-operator-controller-manager`                                    |
| `rbac.serviceAccounts.write.name`         | ServiceAccount name used in write mode for cluster-wide writes                                                      | `agent-write`                                                          |
| `rbac.namespaces.targets[]`               | Namespaces to bind per-namespace roles (`s9s:cluster-read-extra`, `s9s:cluster-write`)                             | `[]`                                                                   |
| `rbac.namespaces.create`                  | Pre-create namespaces listed in `rbac.namespaces.targets`                                                           | `false`                                                                |
| `rbac.clusterRead.includeSecrets`         | Also grant Secrets read cluster-wide (bind `s9s:cluster-read-extra` to default SA)                                  | `false`                                                                |
| `mode.write.enabled`                      | Write mode: bind `s9s:cluster-write` cluster-wide to the write SA                                                   | `false`                                                                |
| `proxy.grpcAddress`                       | ClusterControl proxy gRPC address                                                                                   | `host.docker.internal:50051`                                           |
| `cleanup.enabled`                         | Enable resource cleanup during uninstall                                                                            | `false`                                                                |
| `cleanup.timeoutSeconds`                  | Timeout for each cleanup phase                                                                                      | `300`                                                                  |
| `gitops.enabled`                          | Enable GitOps-aware behavior in the operator                                                                        | `false`                                                                |
| `gitops.tool`                             | GitOps tool: `argo` or `flux`                                                                                       | `argo`                                                                 |
| `gitops.argo.namespace`                   | Argo CD namespace                                                                                                   | `argocd`                                                               |
| `gitops.flux.namespace`                   | Flux namespace                                                                                                      | `flux-system`                                                          |

For the full set of defaults, see the chart's `values.yaml`.

### Using a values file

The YAML snippets in this README are example `values.yaml` content. Save them to a file (e.g., `my-values.yaml`) and pass it to Helm with `-f`:

```bash
helm upgrade --install kuber-agent kuber-agent \
  --repo https://severalnines.github.io/helm-charts/ \
  -n severalnines-system --create-namespace \
  -f my-values.yaml
```

You can combine multiple files and `--set` flags; later entries override earlier ones.

### GitOps

This chart no longer bootstraps Flux or Argo CD. You can still:

- Enable GitOps-aware mode in the controller: `gitops.enabled=true`
- Indicate preferred tool and controller namespaces:
  - `gitops.tool`: `argo` or `flux`
  - `gitops.argo.namespace`: typically `argocd`
  - `gitops.flux.namespace`: typically `flux-system`
- Provide a controller token for PRs/commits via:
  - `controllerAuth.secret.enabled=true` (inline token)
  - copyFrom hook has been removed; create secrets manually (see examples below)

Controllers (Argo/Flux) must be installed separately. See the repository root README for install commands and examples.

#### Secret creation examples

- Argo CD repository secret (HTTPS with PAT):
```bash
GIT_PAT='YOUR_GITHUB_PAT'
kubectl -n argocd create secret generic s9s-argocd-repo \
  --from-literal=type=git \
  --from-literal=url='https://github.com/ORG/REPO.git' \
  --from-literal=username='git' \
  --from-literal=password="$GIT_PAT"
kubectl -n argocd label secret s9s-argocd-repo argocd.argoproj.io/secret-type=repository --overwrite
```

- Controller token secret (used by the operator for PRs/commits):
```bash
GIT_PAT='YOUR_GITHUB_PAT'
kubectl -n severalnines-system create secret generic s9s-gitops-token \
  --from-literal=token="$GIT_PAT"
```

### RBAC configuration

- Cluster roles installed by the chart:
  - `s9s:cluster-read`: cluster-wide read (no Secrets)
  - `s9s:cluster-read-extra`: Secrets read
  - `s9s:cluster-write`: minimal writes (includes ConfigMaps/Secrets/Events, app resources, leases)
- Bindings created by the chart:
  - Cluster-wide: bind `s9s:cluster-read` to the default SA
  - Operator namespace: bind `s9s:cluster-read-extra` and `s9s:cluster-write` to the default SA
  - Per target namespace (`rbac.namespaces.targets`): bind `s9s:cluster-read-extra` and `s9s:cluster-write` to the default SA
  - Optional: when `rbac.clusterRead.includeSecrets=true` bind `s9s:cluster-read-extra` cluster-wide
  - Optional: when `mode.write.enabled=true` bind `s9s:cluster-write` cluster-wide to the write SA

Examples:

```
# Per-namespace read-extra and write in two namespaces (create them too)
helm upgrade --install kuber-agent kuber-agent \
  --repo https://severalnines.github.io/helm-charts/ \
  -n severalnines-system --create-namespace \
  --set rbac.namespaces.targets='{apps1,apps2}' \
  --set rbac.namespaces.create=true

# Allow Secrets read cluster-wide
helm upgrade --install kuber-agent kuber-agent \
  --repo https://severalnines.github.io/helm-charts/ \
  -n severalnines-system \
  --set rbac.clusterRead.includeSecrets=true

# Enable write mode: cluster-wide writes via agent-write SA
helm upgrade --install kuber-agent kuber-agent \
  --repo https://severalnines.github.io/helm-charts/ \
  -n severalnines-system \
  --set mode.write.enabled=true \
  --set rbac.serviceAccounts.write.name=agent-write
```
