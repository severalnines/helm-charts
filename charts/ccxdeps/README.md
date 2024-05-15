# CCX Dependencies

# Install

## Add CCX helm chart repo
```helm repo add s9s https://severalnines.github.io/helm-charts/```

## Install dependencies

### Update helm repos
```helm repo update```

### Install ccx dependencies helm chart
```helm install ccxdeps s9s/ccxdeps --debug```


you can customize your `values.yaml` file and run

```helm install ccxdeps s9s/ccxdeps --debug --values MY_VALUES.yaml```


Wait for stuff to be running.
Monitor with `kubectl get all`.

