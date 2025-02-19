#!/bin/bash

OUTPUT_FILE="ccx-logs.tar.gz"
NAMESPACE=""

services="ccx-auth-service ccx-billing-service ccx-datastores-maintenance ccx-hook-service ccx-monitor-service ccx-notify-worker ccx-rest-admin-service ccx-rest-user-service ccx-runner-service ccx-state-worker ccx-stores-listener ccx-stores-service ccx-stores-worker ccx-ui-admin ccx-ui-app ccx-ui-auth ccx-user cmon-master cmon-proxy"

help() {
    echo "Usage: $0 [-n namespace] [-o output] [-h]"
    echo "  -n namespace: Namespace to gather logs from. Default is current namespace."
    echo "  -o output: Output .tar.gz  file name. Default is ccx-logs.tar.gz."
    echo "  -h: Display this help."
    echo "  All parameters are optional."
}

while getopts "n:o:h" opt; do
  case ${opt} in
    n)
      NAMESPACE="--namespace ${OPTARG}"
      ;;
    o)
      OUTPUT_FILE=${OPTARG}
      ;;
    h)  # Option -h displays help
      help
      exit 0
      ;;
    \?)  # Handle invalid options
      echo "Invalid option: $OPTARG" 1>&2
      help
      exit 1
      ;;
    :)  # Handle missing option arguments
      echo "Option -$OPTARG requires an argument." 1>&2
      exit 1
      ;;
  esac
done

kubectl ${NAMESPACE} get pod cmon-master-0 >/dev/null 2>&1

if [ $? != 0 ]
then
    echo cmon-master-0 pod not found. Are you running in correct cluster and namespace and kubectl is in your PATH?
    exit 1;
fi

dir=$(mktemp -d)

echo Gathering k8s services and pods status...
kubectl ${NAMESPACE} get pod > ${dir}/k8s.pods.txt 2>&1
kubectl ${NAMESPACE} get services > ${dir}/k8s.services.txt 2>&1
kubectl ${NAMESPACE} get deploy -o wide > ${dir}/k8s.deployments.txt 2>&1
kubectl ${NAMESPACE} get statefulset -o wide > ${dir}/k8s.statefulsets.txt 2>&1
kubectl ${NAMESPACE} get ingress -o wide > ${dir}/k8s.ingress.txt 2>&1
kubectl ${NAMESPACE} get all -o wide > ${dir}/k8s.all.txt 2>&1

for i in ${services}
do
    echo Gathering logs for ${i}...
    kubectl ${NAMESPACE} logs -l app=${i} --timestamps=true --max-log-requests=25 --prefix=true --all-containers=true --tail=-1 > ${dir}/${i}.log.txt 2>&1
done

## get logs from dependencies
deployments="$(kubectl ${NAMESPACE} get deployments -o=jsonpath='{.items[*].metadata.name}')"
for i in ${deployments}
do
    echo Gathering logs for ${i}...
    kubectl ${NAMESPACE} logs deployment/${i} --timestamps=true --max-log-requests=25 --prefix=true --all-containers=true --all-pods=true --tail=-1 > ${dir}/deployment-${i}.log.txt 2>&1
done

statefulsets="$(kubectl ${NAMESPACE} get statefulsets -o=jsonpath='{.items[*].metadata.name}')"
for i in ${statefulsets}
do
    echo Gathering logs for ${i}...
    kubectl ${NAMESPACE} logs statefulset/${i} --timestamps=true --max-log-requests=25 --prefix=true --all-containers=true --all-pods=true --tail=-1 > ${dir}/statefulset-${i}.log.txt 2>&1
done

echo Gathering s9s info...
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list --print-json > ${dir}/s9s.job.list.json 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list > ${dir}/s9s.job.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s cluster --list --long > ${dir}/s9s.cluster.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s cluster --list --long --print-json > ${dir}/s9s.cluster.list.json 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s node --list --long > ${dir}/s9s.node.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s node --list --long --print-json > ${dir}/s9s.node.list.json 2>&1

echo Gathering last failed job logs if any...
jobs=$(kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list --show-failed | grep -v "Total" | tail -n +2 | awk '{print $1}')

for i in ${jobs}
do
    echo Gathering logs for job ${i}...
    kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --log --print-request --color=never --job-id ${i} > ${dir}/s9s.job.${i}.log.txt 2>&1
    kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --log --color=never --job-id ${i} --print-json > ${dir}/s9s.job.${i}.log.json 2>&1
done

echo Dumping CCX tables...
export DB_DSN=$(kubectl ${NAMESPACE} get secret db -o jsonpath='{.data.DB_DSN}' | base64 --decode)
export DEPLOYER_DB_DSN=$(kubectl ${NAMESPACE} get secret db-deployer -o jsonpath='{.data.DB_DSN}' | base64 --decode)
kubectl ${NAMESPACE} run -it --rm psql --image=postgres:15-alpine --restart=Never -- pg_dump ${DB_DSN} -x -O -t backups -t cmons -t cluster_config_parameters -t cluster_firewalls -t cluster_hosts -t clusters -t controllers -t databases -t darwin_migrations -t locks -t organizations -t parameter_group -t vpc -t vpc_subnets > ${dir}/ccx_tables_dump.sql
kubectl ${NAMESPACE} run -it --rm psql --image=postgres:15-alpine --restart=Never -- pg_dump ${DB_DSN} -x -O -t job_messages -t jobs > ${dir}/ccx_jobs_dump.sql
kubectl ${NAMESPACE} run -it --rm psql --image=postgres:15-alpine --restart=Never -- pg_dump ${DEPLOYER_DB_DSN} -x -O > ${dir}/ccx_deployer_tables_dump.sql

echo Archiving logs...
tar -zcf ${OUTPUT_FILE} -C ${dir} .

echo Cleaning up...
rm -rf ${dir}

echo Done.
echo Logs available at ${OUTPUT_FILE}