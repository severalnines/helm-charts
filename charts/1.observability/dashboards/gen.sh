#!/bin/bash
cat <<EOT > kustomization.yaml
# Global options
generatorOptions:
  disableNameSuffixHash: true
  labels:
    grafana_dashboard: "true"
commonAnnotations:
  grafana_folder: "CCX"

# Generate a ConfigMap for each dashboard
configMapGenerator:
#################################################
# Views Dashboards
#################################################
EOT

for i in $(find . -name *.json)
do
  dir=$(dirname $i)
  file=$(basename $i)
  path=${i#*/}
  name=$(echo $file | tr '[:upper:]' '[:lower:]' | sed s/_/-/g)
  name="dashboard-${name%.json}"

  cat <<EOT >> kustomization.yaml
- name: ${name}
  files: [ ${path} ]

EOT

done

