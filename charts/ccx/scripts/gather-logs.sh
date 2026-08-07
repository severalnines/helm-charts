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

# Dump a database from a throwaway pod and copy the result out with `kubectl cp`.
#
# We deliberately do NOT stream pg_dump's stdout over `kubectl run -i`/attach.
# That path is unreliable for anything but tiny dumps: the attach stream races
# the container exit ("couldn't attach to pod ..., falling back to streaming
# logs"/"container not found"), and a multi-hundred-MB stream hits an i/o
# timeout on the API-server connection and is SILENTLY TRUNCATED (no pg_dump
# trailer) - or, on some environments, produces 0 bytes with an empty stderr
# because `--rm` deleted the pod before any error surfaced.
#
# Instead: pg_dump writes to a file INSIDE the pod (compressed with gzip, so the
# transfer is ~10x smaller), pg_dump's stderr is captured to a sidecar .err file
# in the pod, and once it finishes we `kubectl cp` the finished files out. The
# pod uses a UNIQUE name (no collisions), is created WITHOUT `--rm` (so it
# survives long enough for the copy and so failures leave evidence), and is
# deleted explicitly afterwards. The connection string is passed via an env var
# so it never appears on a command line.
#
# Usage: dump_db <output-basename> <dsn> [pg_dump options...]
#        produces <output-basename>.sql.gz and <output-basename>.err
dump_db() {
    local out="$1" dsn="$2"; shift 2
    local pod="ccx-logs-pgdump-$$-${RANDOM}"
    kubectl ${NAMESPACE} delete pod "${pod}" --ignore-not-found --now >/dev/null 2>&1
    # The container dumps to /tmp, marks completion with /tmp/dump.done, then idles
    # so `kubectl cp`/`exec` (which need a running container) can reach the files.
    kubectl ${NAMESPACE} run "${pod}" --image=postgres:17-alpine --restart=Never \
        --env="PGCONN=${dsn}" --command -- \
        sh -c 'pg_dump "$@" "$PGCONN" 2>/tmp/dump.err | gzip > /tmp/dump.sql.gz; touch /tmp/dump.done; sleep 86400' \
        sh "$@" >/dev/null 2>&1
    kubectl ${NAMESPACE} wait --for=condition=Ready "pod/${pod}" --timeout=300s >/dev/null 2>&1
    # Poll for completion (large dumps take minutes); cap the wait at ~1h.
    local tries=0
    until kubectl ${NAMESPACE} exec "${pod}" -- test -f /tmp/dump.done >/dev/null 2>&1; do
        tries=$((tries + 1))
        [ ${tries} -gt 720 ] && { echo "  WARNING: ${out} dump timed out" 1>&2; break; }
        sleep 5
    done
    # Copy results out, verifying the copied size against the in-pod size.
    # `kubectl cp` streams over the API server's exec channel, which can
    # silently TRUNCATE a large file if the connection times out. Retrying
    # recovers a transient cut; if it still can't complete we warn loudly
    # rather than hand over a silently-corrupt dump.
    local want got attempt
    want=$(kubectl ${NAMESPACE} exec "${pod}" -- sh -c 'wc -c < /tmp/dump.sql.gz' 2>/dev/null | tr -d '[:space:]')
    for attempt in 1 2 3; do
        kubectl ${NAMESPACE} cp "${pod}:/tmp/dump.sql.gz" "${out}.sql.gz" >/dev/null 2>&1
        got=$(wc -c < "${out}.sql.gz" 2>/dev/null | tr -d '[:space:]')
        [ -n "${want}" ] && [ "${got}" = "${want}" ] && break
        echo "  retrying copy of $(basename "${out}").sql.gz (${got:-0}/${want:-?} bytes)" 1>&2
    done
    [ "${got}" = "${want}" ] || echo "  WARNING: $(basename "${out}").sql.gz incomplete (${got:-0}/${want:-?} bytes) - re-run if needed" 1>&2
    kubectl ${NAMESPACE} cp "${pod}:/tmp/dump.err" "${out}.err" >/dev/null 2>&1
    kubectl ${NAMESPACE} delete pod "${pod}" --now >/dev/null 2>&1
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
dump_db "${dir}/ccx_tables_dump" "${DB_DSN}" -x -O \
    --exclude-table='users*' \
    --exclude-table='admin_users' \
    --exclude-table='session*' \
    --exclude-table='web_tokens' \
    --exclude-table='oauth2_*' \
    --exclude-table='jobs' \
    --exclude-table='job_messages'
dump_db "${dir}/ccx_jobs_dump" "${DB_DSN}" -x -O -t job_messages -t jobs
dump_db "${dir}/ccx_deployer_tables_dump" "${DEPLOYER_DB_DSN}" -x -O

echo Archiving logs...
tar -zcf ${OUTPUT_FILE} -C ${dir} .

echo Cleaning up...
rm -rf ${dir}

echo Done.
echo Logs available at ${OUTPUT_FILE}