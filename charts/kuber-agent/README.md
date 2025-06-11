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
| `rbac.create` | Create RBAC resources | `true` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `agent-operator-controller-manager` |
| `proxy.grpcAddress` | ClusterControl proxy gRPC address | `host.docker.internal:50051` |
| `cleanup.enabled` | Enable resource cleanup during uninstall | `false` |
| `cleanup.timeoutSeconds` | Timeout for each cleanup phase | `300` |

## Uninstalling the Chart

### Resource Cleanup

For a complete cleanup that removes all database resources, operators, and CRDs in the proper order:

```bash
# First, enable cleanup by upgrading the release
helm upgrade kuber-agent kuber-agent --repo https://severalnines.github.io/helm-charts/ \
  --set cleanup.enabled=true

# Then uninstall - cleanup hooks will run automatically
helm uninstall kuber-agent
```

This will automatically:
1. **Phase 1**: Delete all DatabaseClusters across all namespaces
2. **Phase 2**: Delete all DatabaseOperators across all namespaces  
3. **Phase 3**: Delete all CRDs installed by the agent-operator
4. **Phase 4**: Delete the operator itself (standard Helm uninstall)

### Standard Uninstall (Leaves Resources)

To uninstall only the operator (leaving all database resources and CRDs):

```bash
helm uninstall kuber-agent
```

### Manual Cleanup

If you need to manually clean up resources:

```bash
# Remove all resources managed by the operator first
kubectl delete databaseoperators.agent.severalnines.com --all -A
kubectl delete databaseclusters.agent.severalnines.com --all -A
kubectl delete databasebackups.agent.severalnines.com --all -A
kubectl delete databasebackupschedules.agent.severalnines.com --all -A
kubectl delete configversions.agent.severalnines.com --all -A

# Delete CRDs
kubectl delete crd databaseclusters.agent.severalnines.com
kubectl delete crd databaseoperators.agent.severalnines.com
kubectl delete crd databasebackups.agent.severalnines.com
kubectl delete crd databasebackupschedules.agent.severalnines.com
kubectl delete crd configversions.agent.severalnines.com

# Uninstall the operator
helm uninstall kuber-agent
```
