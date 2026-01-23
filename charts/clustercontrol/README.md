# ClusterControl helm-chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/clustercontrol)](https://artifacthub.io/packages/helm/severalnines/clustercontrol)
![Helm: v3](https://img.shields.io/static/v1?label=Helm&message=v3&color=informational&logo=helm)
[![Slack](https://img.shields.io/badge/Join_Slack-%23sovereign_dbaas-purple)](https://sovereign-dbaas.slack.com/join/shared_invite/zt-b15k9477-jLllD6qJOUm3bGnOWynVig)

# Dependencies
This helm chart is designed to provide everything you need to get ClusterControl running in a vanila kubernetes cluster.
This includes dependencies like
* nginx ingress controller
* mysql operator and innodbcluster
* victoria metrics

If you do not wish to install any of those, please see [Dependencies](#helm-chart-dependencies) below.

# Install

## Add a S9s helm repository

Add a chart helm repository with follow commands:

```console
helm repo add s9s https://severalnines.github.io/helm-charts/
helm repo update
```

## Create a namespace
It's recommended to create a namespace for ClusterControl.
It's also **required** to run in custom namespace (not default) when using mysql-operator - default install
```
kubectl create ns clustercontrol
kubectl config set-context --current --namespace=clustercontrol
```

## Install

```
helm install clustercontrol s9s/clustercontrol
```

## Providing your own SSH keys for ClusterControl to use
ClusterControl provides an example SSH key for you to use, however 
You should provide your SSH keys for ClusterControl to use and connect to your target machines.
These should already be configured on target server's `authorized_keys`

### Create k8s secrets with your SSH keys

`key1` is the filename of your ssh key in ClusterControl - this will be created under `/root/.ssh-keys-user`

```
kubectl create secret generic my-ssh-keys --from-file=key1=/path/to/my/.ssh/id_rsa
```

**NOTE**: You can use multiple `--from-file` - be sure to provide unique keynames - `key1`, `key2`, `key3`

### Install or Upgrade ClusterControl

Providing cmon.sshKeysSecretName value with our secret name created above

```
helm upgrade --install clustercontrol s9s/clustercontrol --set cmon.sshKeysSecretName=my-ssh-keys
```

## Custom configuration via values.yaml

### Create your own values.yaml

Look at the `values.yaml` and create your own file with proper overrides.

```
helm show values s9s/clustercontrol > values.yaml
```

### Install / Upgrade using your custom values.yaml

```
helm install clustercontrol s9s/clustercontrol -f values.yaml
```

## Notes
cmon API is accessible within the cluster via cmon-master:9501

ClusterControl V2 is accessible within the cluster via cmon-master:3000

Is is *HIGHLY* recommended to use ingress as ClusterControl V2 requires cmon API to be exposed and available externaly.


## Access UI (ingress)
If you enabled the bundled NGINX ingress controller, wait for its service to get an external IP/hostname:

```bash
kubectl get svc -n clustercontrol clustercontrol-ingress-nginx-controller
```

Then set `fqdn` to a DNS name that resolves to that IP. For quick testing you can use nip.io:

```bash
helm upgrade --install clustercontrol s9s/clustercontrol --set fqdn=<external-ip>.nip.io
```


## Helm chart dependencies

### If you already have Oracle MySQL Operator or NGINX ingress controller installed

```
helm install clustercontrol s9s/clustercontrol --debug --set fqdn=clustercontrol.example.com --set installMysqlOperator=false --set ingressController.enabled=false
```

This helm chart has certain dependencies that makes ClusterControl easier to install.
None of these is necessary if you provide your own equivalent or you already have it installed.

* oracle-mysql-operator
Oracle MySQL operator, required for running MySQL DB withing the k8s cluster.
You can disable this by setting
```
installMysqlOperator: false
```

* oracle-mysql-innodbcluster
An MySQL Innodb cluster required for ClusterControl
You can disable this by setting
```
createDatabases: false
```
But you will need to provide a different MySQL / MariaDB or compatibile for ClusterControl to use.
For exact documentation refer to the official helm chart documentation
https://github.com/mysql/mysql-operator/blob/trunk/helm/mysql-innodbcluster/values.yaml

* nginx-ingress-controller
Nginx ingress controller. You need an ingress controller to access ClusterControl.
If you already have ingress controller installed or wish to use a different one, you can disable this by
```
ingressController:
  enabled: false
```
More information - https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx

### If you wish to use your own victoria metrics or other prometheus compatibile monitoring system

* victoria-metrics-single
https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-single#parameters
These defaults provide minimal needed for ClusterControl metrics and dashboards to work
Feel free to adjust as needed, however keep in mind required labels and annotations and service discovery.
If you already have your own VictoriaMetrics or Prometheus cluster and don't want to install this, you can disable by setting
```
prometheusHostname: my-prometheus-server
monitoring:
  enabled: false
```

## Uninstall
To uninstall ClusterControl from your kubernetes cluster simply run
```
helm uninstall clustercontrol
```

### Persistent resources
You might need to delete pvc created for the innodb database cluster manually.
To do so, simply run
```
kubectl delete pvc datadir-clustercontrol-0
```

### Dependent resources
Although, uninstall **should** remove every dependency created by this helm chart, sometimes the database cluster hang. To clean up, try removing them manualy by running
```
kubectl delete innodbclusters.mysql.oracle.com clustercontrol
```

or editing above resource and removing finalizers.