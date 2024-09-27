#!/bin/bash

OUTPUT_FILE="ccx-logs.tar.gz"
NAMESPACE=""

services="ccx-admin-service ccx-auth-service ccx-backup-storage ccx-billing-rest-service ccx-billing-service ccx-controller-storage ccx-datastores-maintenance ccx-datastore-storage ccx-datastore-storage-status-update ccx-deployer-service ccx-hook-service ccx-job-storage ccx-monitor-service ccx-notification-service ccx-notify-worker ccx-rbac-service ccx-rest-service ccx-runner-notifications ccx-runner-service ccx-stores-listener ccx-stores-service ccx-stores-worker ccx-ui-app ccx-ui-auth ccx-user ccx-vpc-storage cmon-master cmon-proxy"

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

for i in ${services}
do
    echo Gathering logs for ${i}...
    kubectl ${NAMESPACE} logs -l app=${i} --all-containers=true --tail=-1 > ${dir}/${i}.log.txt 2>&1
done

echo Gathering s9s info...
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list --print-json > ${dir}/s9s.job.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list > ${dir}/s9s.job.list.json 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s cluster --list --long > ${dir}/s9s.cluster.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s cluster --list --long --print-json > ${dir}/s9s.cluster.list.json 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s node --list --long > ${dir}/s9s.node.list.txt 2>&1
kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s node --list --long --print-json > ${dir}/s9s.node.list.json 2>&1

echo Gathering last 10 failed job logs if any...
jobs=$(kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --list --show-failed --limit=10 | head -n -2 | tail -n +2 | awk '{print $1}')

for i in ${jobs}
do
    echo Gathering logs for job ${i}...
    kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --log --job-id ${i} > ${dir}/s9s.job.${i}.log.txt 2>&1
    kubectl ${NAMESPACE} exec -ti cmon-master-0 -c cmon-master -- s9s job --log --job-id ${i} --print-json > ${dir}/s9s.job.${i}.log.json 2>&1
done

echo Dumping CCX tables...
export DB_DSN=$(kubectl ${NAMESPACE} get secret db -o jsonpath='{.data.DB_DSN}' | base64 --decode)
kubectl ${NAMESPACE} run -it --rm psql --image=postgres:15-alpine --restart=Never -- pg_dump ${DB_DSN} -x -O -t cluster_config_parameters -t cluster_firewalls -t cluster_hosts -t clusters -t controllers -t databases -t darwin_migrations -t vpc -t vpc_subnets > ${dir}/ccx_tables_dump.sql
kubectl ${NAMESPACE} run -it --rm psql --image=postgres:15-alpine --restart=Never -- pg_dump ${DB_DSN} -x -O -t job_messages -t jobs > ${dir}/ccx_jobs_dump.sql

echo Archiving logs...
tar -zcf ${OUTPUT_FILE} -C ${dir} .

echo Cleaning up...
rm -rf ${dir}
kill -9 %1 2>/dev/null

echo Done.
echo Logs available at ${OUTPUT_FILE}

