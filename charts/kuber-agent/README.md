# ClusterControl Kubernetes Agent Operator


This Helm chart deploys the ClusterControl Kubernetes Agent Operator, which manages the lifecycle of database resources in a Kubernetes cluster.


## Installing the Chart

### From Git Repository

You can install the chart directly from the Git repository:

```bash
helm install kuber-agent kuber-agent --repo https://severalnines.github.io/helm-charts/ \
  --create-namespace \
  --namespace severalnines-system
  --set agent.publicKey="<public-key>" \
  --set proxy.grpcAddress="host.docker.internal:50051" \
```

## Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Operator image repository | `europe-docker.pkg.dev/severalnines-public/clustercontrol/agent-operator` |
| `image.tag` | Operator image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `Always` |
| `agent.publicKey` | Public key for agent authentication | `""` |
| `agent.name` | Name for the agent (if not set, uses the first node name in the cluster) | `""` |
| `namespaceOverride` | Override the namespace for resources | `""` |
| `createNamespace` | Create the namespace | `true` |
| `controllerManager.replicas` | Number of operator replicas | `1` |
| `crds.install` | Whether to install CRDs | `true` |
| `crds.keepOnDelete` | Whether to keep CRDs on chart deletion | `true` |
| `rbac.create` | Create RBAC resources | `true` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `agent-operator-controller-manager` |
| `proxy.grpcAddress` | ClusterControl proxy gRPC address | `host.docker.internal:50051` |

## Uninstalling the Chart

To uninstall/delete the `kuber-agent` deployment:

```bash
# Remove all resources managed by the operator first
kubectl delete databaseoperators.agent.severalnines.com --all -A
kubectl delete databaseclusters.agent.severalnines.com --all -A
kubectl delete databasebackups.agent.severalnines.com --all -A
kubectl delete databasebackupschedules.agent.severalnines.com --all -A
kubectl delete configversions.agent.severalnines.com --all -A

# Uninstall the operator
helm uninstall kuber-agent
```


### From Local Directory

If you've cloned the repository:

```bash
helm install kuber-agent ./agent-operator/chart
```

## Configuration

### Agent Authentication

The operator requires a public key for agent authentication. You can provide it during installation:

```bash
helm install kuber-agent ./charts/kuber-agent \
  --create-namespace \
  --namespace severalnines-system
  --set agent.publicKey="<public-key>" \
  --set proxy.grpcAddress="host.docker.internal:50051"
```
