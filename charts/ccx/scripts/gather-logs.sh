#!/bin/bash

OUTPUT_FILE="ccx-logs.tar.gz"
NAMESPACE=""

services="ccx-auth-service ccx-billing-service ccx-datastores-maintenance ccx-hook-service ccx-monitor-service ccx-notify-worker ccx-rest-admin-service ccx-rest-user-service ccx-runner-service ccx-state-worker ccx-stores-listener ccx-stores-service ccx-ui-admin ccx-ui-app ccx-ui-auth ccx-user cmon cmon-proxy"

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

kubectl ${NAMESPACE} get pod cmon-0 >/dev/null 2>&1

if [ $? != 0 ]
then
    echo cmon-0 pod not found. Are you running in correct cluster and namespace and kubectl is in your PATH?
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
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s job --list --print-json --color=never > ${dir}/s9s.job.list.json 2>&1
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s job --list --color=never > ${dir}/s9s.job.list.txt 2>&1
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s cluster --list --long --color=never > ${dir}/s9s.cluster.list.txt 2>&1
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s cluster --list --long --print-json --color=never > ${dir}/s9s.cluster.list.json 2>&1
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s node --list --long --color=never > ${dir}/s9s.node.list.txt 2>&1
kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s node --list --long --print-json --color=never > ${dir}/s9s.node.list.json 2>&1

echo Gathering last failed job logs if any...
jobs=$(kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s job --list --show-failed --color=never | grep -v "Total" | tail -n +2 | awk '{print $1}')

for i in ${jobs}
do
    echo Gathering logs for job ${i}...
    kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s job --log --print-request --color=never --job-id ${i} > ${dir}/s9s.job.${i}.log.txt 2>&1
    kubectl ${NAMESPACE} exec cmon-0 -c cmon -- s9s job --log --color=never --job-id ${i} --print-json > ${dir}/s9s.job.${i}.log.json 2>&1
done

echo Dumping CCX tables...
export DB_DSN=$(kubectl ${NAMESPACE} get secret db -o jsonpath='{.data.DB_DSN}' | base64 --decode)
export DEPLOYER_DB_DSN=$(kubectl ${NAMESPACE} get secret db-deployer -o jsonpath='{.data.DB_DSN}' | base64 --decode)

# Run pg_dump inside a throwaway pod. Each call uses a UNIQUE pod name so that a
# previous dump pod that is still terminating (or was left behind by an
# interrupted run) cannot cause a `pods "psql" already exists` failure. Any
# leftover pod with the same name is removed first as an extra safeguard.
# The caller keeps stdout (the SQL) and stderr (kubectl/pg_dump messages)
# separate so pod lifecycle text never ends up inside the .sql dump.
pg_dump_in_pod() {
    local podname="ccx-logs-pgdump-$$-${RANDOM}"
    kubectl ${NAMESPACE} delete pod "${podname}" --ignore-not-found --now >/dev/null 2>&1
    kubectl ${NAMESPACE} run -i --rm "${podname}" --quiet --image=postgres:15-alpine --restart=Never -- pg_dump "$@"
}

# Dump the CCX database with an EXCLUDE list rather than a hand-maintained -t
# allowlist. This keeps the bundle complete across schema changes - notably the
# billing usage tables (billing_usage_clusters, billing_daily_usage_clusters,
# billing_snapshot, ...) that hold the datastore lifecycle / deleted_at used by
# the billing report - which the old allowlist silently omitted. It also avoids
# pg_dump aborting when a single listed table does not exist on a given version.
#
# The excluded tables are:
#   * sensitive data that must never leave the cluster: user PII (users, users_*,
#     admin_users), auth sessions (session/sessions), and tokens/credentials
#     (web_tokens, oauth2_*). KEEP THIS LIST UP TO DATE if new sensitive tables
#     are added.
#   * jobs / job_messages, which are large and dumped separately below.
# Note: pg_dump takes the connection string / dbname as its final positional
# argument, so it is passed last (after all options) for reliable parsing.
pg_dump_in_pod -x -O \
    --exclude-table='users*' \
    --exclude-table='admin_users' \
    --exclude-table='session*' \
    --exclude-table='web_tokens' \
    --exclude-table='oauth2_*' \
    --exclude-table='jobs' \
    --exclude-table='job_messages' \
    "${DB_DSN}" > "${dir}/ccx_tables_dump.sql" 2> "${dir}/ccx_tables_dump.err"
pg_dump_in_pod -x -O -t job_messages -t jobs "${DB_DSN}" > "${dir}/ccx_jobs_dump.sql" 2> "${dir}/ccx_jobs_dump.err"
pg_dump_in_pod -x -O "${DEPLOYER_DB_DSN}" > "${dir}/ccx_deployer_tables_dump.sql" 2> "${dir}/ccx_deployer_tables_dump.err"

echo Archiving logs...
tar -zcf ${OUTPUT_FILE} -C ${dir} .

echo Cleaning up...
rm -rf ${dir}

echo Done.
echo Logs available at ${OUTPUT_FILE}