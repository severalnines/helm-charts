# CCX helm-chart

## Deploying on your local cluster

### Prerequisites

* image-pull secrets
* cert-manager (optional) or ssl certificate (wildcard)
* ingress controller
* FQDN pointing to your ingress controller (need a public IP to be able to do that) or externaldns (optional)

# Install

## Add CCX helm chart repo

```helm repo add --pass-credentials --username YOUR_GITHUB_NAME --password YOUR_GITHUB_TOKEN ccx https://severalnines.github.io/helm-ccx/```

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

```helm install ccx ccx/ccx --values YOUR_VALUES_FILE-values.yaml --debug```

If your values are divided between multiple files, you can use the `--values` option multiple times.

### Applying your local changes to your env

cd into your helm-ccx dir and

> :warning: Always double-check your current kubectl context and namespace beforehand :warning:

```shell
helm upgrade ccx . -f my-values.yaml -f my-deployer-values.yaml
```
