# CCX helm-chart

# Quickstart

This guide assumes using dependencies helper repo - https://github.com/severalnines/helm-ccxdeps

Add repos

```
helm repo add ccxdeps https://severalnines.github.io/helm-ccxdeps/
helm repo add s9s https://severalnines.github.io/helm-charts/
helm repo update
```

Inspect and modify `minimal-values.yaml`

Install

```
# Create k8s secret from AWS credentials stored in ~/.aws/credentials
kubectl create secret generic aws --from-literal=AWS_ACCESS_KEY_ID=$(awk 'tolower($0) ~ /aws_access_key_id/ {print $NF; exit}' ~/.aws/credentials) --from-literal=AWS_SECRET_ACCESS_KEY=$(awk 'tolower($0) ~ /aws_secret_access_key/ {print $NF; exit}' ~/.aws/credentials)
# Install CCX dependencies
helm install ccxdeps ccxdeps/ccxdeps --debug
# Install CCX
helm repo add s9s https://severalnines.github.io/helm-charts/
helm repo update
helm install ccx s9s/ccx --values minimal-values.yaml --debug --wait
```

Enjoy!


## Deploying on your local cluster

### Prerequisites

* image-pull secrets
* cert-manager (optional) or ssl certificate (wildcard)
* ingress controller
* FQDN pointing to your ingress controller (need a public IP to be able to do that) or externaldns (optional)

# Install

## Add CCX helm chart repo

```helm repo add s9s https://severalnines.github.io/helm-charts/```

## Install CCX

### values.yaml

Look at the `values.yaml` and create your own file with proper overrides. 

### Secrets

Inspect `secrets-template.yaml`, provide your secrets and deploy with `kubectl apply -f secrets-template.yaml`

#### Cloud credentials
K8s secrets can have any name, but the template suggests `s9s-openstack`, `s9s-s3`.

Secret keys must have names `S9S_XXX`, replacing `MYCLOUD_XXX` in template.

The `S9S` part is exactly the uppercase form of the cloud name in ccx and deployer config files.

Then list the secrets in the values file:

```
ccx:
  cloudSecrets:
    - s9s-openstack
    - s9s-s3
```

### Install CCX helm chart

```helm install ccx s9s/ccx  --values YOUR_VALUES_FILE-values.yaml --debug```

If your values are divided between multiple files, you can use the `--values` option multiple times.

### Applying your local changes to your env

cd into your helm-ccx dir and

> :warning: Always double-check your current kubectl context and namespace beforehand :warning:

```shell
helm upgrade ccx . -f my-values.yaml -f my-deployer-values.yaml
```
