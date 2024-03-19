# Cluster Control helm-chart

![Helm: v3](https://img.shields.io/static/v1?label=Helm&message=v3&color=informational&logo=helm)

# Install

### Prerequisites

* helm

## Add a chart helm repository

Add a chart helm repository with follow commands:

```console
helm repo add s9s https://severalnines.github.io/helm-charts/

helm repo update
```


## Install

```
helm install cc s9s/cc --debug
```

## Set cmon user and password

```
helm install cc s9s/cc --debug --set cmon.user=USER --set cmon.password=PASSWORD
```

or simply edit your `values.yaml` file.
**NOTE** Setting initial password only works during ClusterControl installation.
After the installation is complete, you need to change your password in ClusterControl UI or using s9s cli.

## Providing your own SSH keys

### Create k8s secrets with your SSH keys

`key1` is the filename of your ssh key in cluster control - this will be created under `/root/.ssh-keys-user`

```
kubectl create secret generic my-ssh-keys --from-file=key1=/path/to/my/.ssh/id_rsa
```

**NOTE**: You can use multiple `--from-file` - be sure to provide unique keynames - `key1`, `key2`, `key3`

### Install or Upgrade Cluster Control

Providing cmon.sshKeysSecretName value with our secret name created above

```
helm upgrade --install cc s9s/cc --debug --set cmon.sshKeysSecretName=my-ssh-keys
```

## Notes
cmon API is accessible within the cluster via cmon-master:9501

ClusterControl V2 is accessible within the cluster via cmon-master:3000

Is is *HIGHLY* recommended to use ingress as ClusterControl V2 requires cmon API to be exposed and available externaly.


## If you already have Oracle MySQL Operator and NGINX ingress controller installed

```
helm install cc s9s/cc --debug --set fqdn=tratatatata.s9s-dev.net --set installMysqlOperator=false --set ingressController.enabled=false
```

### values.yaml

Look at the `values.yaml` and create your own file with proper overrides. # helm-cc
