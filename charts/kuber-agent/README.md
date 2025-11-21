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

| Parameter                              | Description                                                                            | Default                                                                |
| -------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `image.repository`                     | Operator image repository                                                              | `europe-docker.pkg.dev/severalnines-public/clustercontrol/kuber-agent` |
| `image.tag`                            | Operator image tag                                                                     | `""` (defaults to chart appVersion)                                    |
| `image.pullPolicy`                     | Image pull policy                                                                      | `Always`                                                               |
| `image.useDevelopmentImage`            | Use development image tag instead of `image.tag`                                       | `false`                                                                |
| `image.developmentImageTag`            | Development image tag used when `image.useDevelopmentImage=true`                       | `main-dev-latest`                                                      |
| `agent.publicKey`                      | Public key for agent authentication                                                    | `""`                                                                   |
| `agent.name`                           | Name for the agent (if not set, uses the first node name in the cluster)               | `""`                                                                   |
| `env`                                  | Environment: `production` or `development` (influences default log level)              | `production`                                                           |
| `nameOverride`                         | Override chart name                                                                    | `""`                                                                   |
| `fullnameOverride`                     | Override full name                                                                     | `""`                                                                   |
| `namespaceOverride`                    | Override the namespace for resources                                                   | `""`                                                                   |
| `createNamespace`                      | Create the namespace                                                                   | `true`                                                                 |
| `controllerManager.replicas`           | Number of operator replicas                                                            | `1`                                                                    |
| `controllerManager.healthProbe.port`   | Health/readiness probe port                                                            | `8081`                                                                 |
| `controllerManager.controllers`        | List of enabled controllers (empty = all)                                              | `[]`                                                                   |
| `controllerManager.manager.resources`  | Resource requests/limits for manager container                                         | see values.yaml                                                        |
| `rbac.create`                          | Create RBAC resources                                                                  | `true`                                                                 |
| `rbac.serviceAccounts.agent.name`      | Default ServiceAccount name used by the operator                                       | `agent-operator-controller-manager`                                    |
| `rbac.serviceAccounts.write.name`      | ServiceAccount name used in write mode for cluster-wide writes                         | `agent-write`                                                          |
| `rbac.serviceAccounts.agent.create`    | Create the operator ServiceAccount (reserved; not used by templates currently)         | `true`                                                                 |
| `rbac.serviceAccounts.write.create`    | Create the write ServiceAccount (reserved; not used by templates currently)            | `true`                                                                 |
| `rbac.namespaces.targets[]`            | Namespaces to bind per-namespace roles (`s9s:cluster-read-extra`, `s9s:cluster-write`) | `[]`                                                                   |
| `rbac.namespaces.create`               | Pre-create namespaces listed in `rbac.namespaces.targets`                              | `false`                                                                |
| `rbac.clusterRead.includeSecrets`      | Also grant Secrets read cluster-wide (bind `s9s:cluster-read-extra` to default SA)     | `false`                                                                |
| `mode.write.enabled`                   | Write mode: bind `s9s:cluster-write` cluster-wide to the write SA                      | `false`                                                                |
| `proxy.grpcAddress`                    | ClusterControl proxy gRPC address                                                      | `host.docker.internal:50051`                                           |
| `cleanup.enabled`                      | Enable resource cleanup during uninstall                                               | `false`                                                                |
| `cleanup.timeoutSeconds`               | Timeout for each cleanup phase                                                         | `300`                                                                  |
| `cleanup.image.repository`             | Image repository for cleanup jobs (kubectl image)                                      | `bitnami/kubectl`                                                      |
| `cleanup.image.tag`                    | Image tag for cleanup jobs                                                             | `1.28`                                                                 |
| `cleanup.image.pullPolicy`             | Image pull policy for cleanup jobs                                                     | `IfNotPresent`                                                         |
| `cleanup.resources`                    | Resource requests/limits for cleanup jobs                                              | see values.yaml                                                        |
| `debug.logLevel`                       | Explicit log level (`debug`, `info`, ...) Overrides default based on `env`             | `""`                                                                   |
| `gitops.enabled`                       | Enable GitOps-aware behavior in the operator                                           | `false`                                                                |
| `gitops.tool`                          | GitOps tool: `argo` or `flux`                                                          | `argo`                                                                 |
| `gitops.argo.namespace`                | Argo CD namespace                                                                      | `argocd`                                                               |
| `gitops.flux.namespace`                | Flux namespace                                                                         | `flux-system`                                                          |
| `controllerAuth.secret.enabled`        | Create a secret with controller token for PRs/commits                                  | `false`                                                                |
| `controllerAuth.secret.name`           | Name of the controller token secret                                                    | `""` (defaults to `<release>-gitops-token`)                            |
| `controllerAuth.secret.key`            | Key in the secret containing the token                                                 | `token`                                                                |
| `controllerAuth.secret.value`          | Value of the token (plaintext; for quickstart/testing)                                 | `""`                                                                   |
| `controllerAuth.provider`              | Auth provider for controller actions                                                   | `github`                                                               |
| `controllerAuth.baseURL`               | Base URL for GitHub Enterprise                                                         | `""`                                                                   |
| `appBundleImport.enabled`              | Enable background importer to create AppBundle CRs from Argo/Flux                      | `true`                                                                 |
| `appBundleImport.provider`             | Importer provider: `argo`, `flux`, or empty for both                                   | `""`                                                                   |
| `appBundleImport.interval`             | Importer sweep interval                                                                | `1m`                                                                   |
| `appBundleImport.crNamespace`          | Namespace to create AppBundle CRs (default: POD_NAMESPACE when empty)                  | `""`                                                                   |
| `appBundleImport.manageLifecycle`      | Set `spec.manageLifecycle` on generated CRs                                            | `false`                                                                |
| `dev.enabled`                          | Enable development overrides (command/probes/volumes)                                  | `false`                                                                |
| `dev.command`                          | Container command array used when `dev.enabled=true`                                   | `["/usr/local/bin/devloop-operator.sh"]`                               |
| `dev.startupProbe`                     | Optional startupProbe used when `dev.enabled=true` and not disabled                    | see values.yaml                                                        |
| `dev.disableProbes`                    | Disable liveness/readiness/startup probes when in dev mode                             | `true`                                                                 |
| `dev.persistentCache.enabled`          | Enable persistent Go module/build cache volume (dev mode)                              | `true`                                                                 |
| `dev.persistentCache.create`           | Create the persistent volume claim (dev mode)                                          | `false`                                                                |
| `dev.persistentCache.pvcName`          | PVC name for Go cache (dev mode)                                                       | `operator-cache`                                                       |
| `dev.persistentCache.storageClassName` | StorageClass for cache PVC (dev mode)                                                  | `local-path`                                                           |
| `dev.resources`                        | Extra resource overrides when `dev.enabled=true`                                       | `{}`                                                                   |




## GitOps

Controllers (Argo/Flux) must be installed separately.

- Enable GitOps-aware mode in the controller: `gitops.enabled=true`
- Indicate preferred tool and controller namespaces:
  - `gitops.tool`: `argo` or `flux`
  - `gitops.argo.namespace`: typically `argocd`
  - `gitops.flux.namespace`: typically `flux-system`

#### Secret creation examples

- Argo CD repository secret (HTTPS with PAT):

```bash
GIT_PAT='YOUR_GITHUB_PAT'
kubectl -n argocd create secret generic s9s-argocd-repo \
  --from-literal=type=git \
  --from-literal=url='https://github.com/ORG/REPO/' \
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

## RBAC configuration

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


## Uninstall and resource cleanup

First, enable cleanup by upgrading the release
```bash
helm upgrade kuber-agent kuber-agent --repo https://severalnines.github.io/helm-charts/ \
  --namespace severalnines-system \
  --set cleanup.enabled=true

# Then uninstall - cleanup hooks will run automatically
helm uninstall kuber-agent
```
This will automatically:

1. **Phase 1**: Delete all DatabaseClusters across all namespaces
2. **Phase 2**: Delete all DatabaseOperators across all namespaces
3. **Phase 3**: Delete all CRDs installed by the agent-operator
4. **Phase 4**: Delete the operator itself (standard Helm uninstall)