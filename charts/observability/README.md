# CCX Victoria metrics stack
Monitoring stack for CCX cluster


## Overview

This stack uses:
* Victoria metrics - Prometheus compatibile monitoring for metrics and alerting (vmsingle/vmalert) - https://docs.victoriametrics.com/Single-server-VictoriaMetrics.html
* Alertmanager - https://prometheus.io/docs/alerting/latest/alertmanager/
* Grafana - https://grafana.com/docs/
* kube-state-metrics - https://github.com/kubernetes/kube-state-metrics

## Deployment
In order to deploy this chart along with dependencies and apply dashboards, one needs to pull first.

### Requirements
* kubernetes cluster
* helm - https://helm.sh/docs/intro/install/

### values.yaml
`values.yaml` is a defaults file. Please *DO NOT* edit it.
If you want to override values, please edit `s9s.yaml` or create another values file.

It is very important to edit `s9s.yaml` file and set variables like cluster name, ingress host, etc.

### Namespace
It's preferred to have a dedicated namespace for this stack.

Set your active namespace

`kubectl config set-context --current --namespace=victoriametrics`

### Add chart repo

`helm repo add s9s https://severalnines.github.io/helm-charts/`

`helm repo update`

### Pull the chart

`helm pull s9s/ccx-monitoring --untar`

### Helm dependencies
Update your helm dependencies by running

`helm dependency update ccx-monitoring`

### Installation & Upgrade
`helm upgrade --install ccx-monitoring ccx-monitoring --atomic --namespace victoriametrics --values YOUR_VALUES.yaml --debug `

Please note that this guide as some other documents and urls assumes that you use `ccx-monitoring` release name.

Verify installation by running - check the `status` field.
`helm ls -a --namespace victoriametrics`

#### Grafana dashboards
Grafana dashboards and datasources are kept as a code in the repo.

`kubectl --namespace victoriametrics delete -k ccx-monitoring/dashboards`
`kubectl --namespace victoriametrics create -k ccx-monitoring/dashboards`

Additional dashboards can be placed as `.json` files in folders inside `dashboards` directory.
 
#### Grafana datasources
Grafana dashboards and datasources are kept as a code in the repo.

Navigate to `datasources` directory, edit `grafana_datasource.yaml` and apply via 

`kubectl --namespace victoriametrics apply -k ccx-monitoring/datasources`


#### To get grafana admin password run

`kubectl get secret ccx-monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`

### Removal
*WARNING*

`helm uninstall ccx-monitoring`

or

This will delete all monitoring related resources and objects!

`kubectl delete namespace victoriametrics`
