#!/usr/bin/env bash
#
# Mirror third-party helm charts and container images that our charts depend on
# into our Google Artifact Registry, so upstream repos pruning a release cannot
# break our builds or customer installs.
#
# Charts  -> oci://europe-docker.pkg.dev/severalnines-public/clustercontrol/helm-charts/<name>:<version>
# Images  -> europe-docker.pkg.dev/severalnines-public/clustercontrol/mirror/<upstream-path>:<tag>
#
# There is NO version list in this script. Each chart is the single source of truth:
#   - dependency versions come from its Chart.yaml
#   - upstream chart repos come from its Chart.yaml too; for dependencies already
#     migrated to our GAR, the original upstream is looked up in UPSTREAM_CHART_REPO
#   - image tags come from rendering the chart (helm template), which resolves
#     subchart defaults and values.yaml overrides; only images already pointing at
#     our mirror are copied (the MySQL server/router tag is read from the rendered
#     InnoDBCluster resource, since the operator pulls those at runtime)
# To bump a dependency: edit the chart, run this script, commit. The two maps
# below only change when a NEW dependency/registry is introduced.
#
# Requirements:
#   - helm >= 3.8, yq v4, and crane (preferred) or skopeo for image copies
#   - push access: a service account with Artifact Registry Writer on
#     severalnines-public/clustercontrol (key: cc-dev-buildbot@severalnines-public), then:
#       gcloud auth configure-docker europe-docker.pkg.dev
#       gcloud auth print-access-token <account> | helm registry login -u oauth2accesstoken --password-stdin europe-docker.pkg.dev
#
# Usage:
#   ./scripts/mirror-to-gar.sh [options]
#     --dry-run        show what would be mirrored without pushing
#     --seed-from DIR  use chart tgz from DIR for versions already pruned upstream
#                      (one-time seed; recover tgz from git history)
#
# Already-mirrored artifacts are skipped, so GAR keeps every version forever.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Charts to process. Only clustercontrol is migrated to the GAR mirror today;
# to cover another chart (ccxdeps, observability, ...) add its directory here
# and extend the two maps below as needed.
CHART_DIRS=(
  "${REPO_ROOT}/charts/clustercontrol"
)

GAR_HOST="europe-docker.pkg.dev"
GAR_CHARTS="oci://${GAR_HOST}/severalnines-public/clustercontrol/helm-charts"
GAR_MIRROR="${GAR_HOST}/severalnines-public/clustercontrol/mirror"

# Original upstream helm repo per dependency name — needed only for dependencies
# whose Chart.yaml repository already points at our GAR (otherwise the upstream
# is taken straight from Chart.yaml). Extend when migrating a new dependency.
declare -A UPSTREAM_CHART_REPO=(
  [mysql-operator]="https://mysql.github.io/mysql-operator/"
  [mysql-innodbcluster]="https://mysql.github.io/mysql-operator/"
  [victoria-metrics-single]="https://victoriametrics.github.io/helm-charts/"
  [ingress-nginx]="https://kubernetes.github.io/ingress-nginx"
)

# Upstream registry host per first path segment under ${GAR_MIRROR}/.
# Lets us reverse-map a mirrored image ref back to its upstream source.
declare -A UPSTREAM_REGISTRY=(
  [mysql]="container-registry.oracle.com"
  [ingress-nginx]="registry.k8s.io"
  [victoriametrics]="docker.io"
)

DRY_RUN=0
SEED_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --seed-from) SEED_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    *) echo "usage: $0 [--dry-run] [--seed-from DIR]" >&2; exit 1 ;;
  esac
done

run() { if (( DRY_RUN )); then echo "DRY  $*"; else "$@"; fi; }

copy_image() { # src dst — digest-preserving, all platforms
  if (( DRY_RUN )); then
    echo "DRY  copy $1 -> $2"
  elif command -v crane >/dev/null; then
    crane copy "$1" "$2"
  elif command -v skopeo >/dev/null; then
    skopeo copy --all "docker://$1" "docker://$2"
  else
    echo "ERR  need crane or skopeo to copy images" >&2; exit 1
  fi
}

image_exists() {
  local ref="$1" path tag
  path="${ref#"${GAR_HOST}"/}"; tag="${path##*:}"; path="${path%:*}"
  curl -fsS -o /dev/null "https://${GAR_HOST}/v2/${path}/manifests/${tag}" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    2>/dev/null
}

mirror_chart_deps() { # chart_dir stage
  local chart_dir="$1" stage="$2"
  local name version repo upstream tgz
  mkdir -p "${stage}/tgz"

  while IFS='|' read -r name version repo; do
    tgz="${stage}/tgz/${name}-${version}.tgz"
    if helm pull "${GAR_CHARTS}/${name}" --version "${version}" -d "${stage}/tgz" 2>/dev/null; then
      echo "OK   chart ${name}:${version} already in GAR"
      continue
    fi
    if [[ -n "${SEED_DIR}" && -f "${SEED_DIR}/${name}-${version}.tgz" ]]; then
      echo "SEED chart ${name}:${version} from ${SEED_DIR}"
      cp "${SEED_DIR}/${name}-${version}.tgz" "${stage}/tgz/"
      echo "PUSH chart ${tgz##*/} -> ${GAR_CHARTS}"
      run helm push "${tgz}" "${GAR_CHARTS}"
      continue
    fi
    # upstream = Chart.yaml repository, unless that's already our GAR
    upstream="${repo}"
    if [[ "${upstream}" == "${GAR_CHARTS}"* ]]; then
      upstream="${UPSTREAM_CHART_REPO[${name}]:-}"
      [[ -n "${upstream}" ]] || { echo "ERR  no upstream repo mapped for '${name}' — add it to UPSTREAM_CHART_REPO" >&2; exit 1; }
    fi
    echo "PULL chart ${name}:${version} from ${upstream}"
    if [[ "${upstream}" == oci://* ]]; then
      pulled=$(helm pull "${upstream}/${name}" --version "${version}" -d "${stage}/tgz" && echo ok || true)
    else
      pulled=$(helm pull "${name}" --repo "${upstream}" --version "${version}" -d "${stage}/tgz" && echo ok || true)
    fi
    if [[ "${pulled}" != "ok" ]]; then
      echo "ERR  ${name}:${version} is gone upstream and not yet in GAR." >&2
      echo "     Recover the tgz from git history and re-run with --seed-from:" >&2
      echo "       git show <ref>:${chart_dir#"${REPO_ROOT}"/}/charts/${name}-${version}.tgz > seed/${name}-${version}.tgz" >&2
      exit 1
    fi
    echo "PUSH chart ${tgz##*/} -> ${GAR_CHARTS}"
    run helm push "${tgz}" "${GAR_CHARTS}"
  done < <(yq -r '.dependencies[]? | .name + "|" + .version + "|" + .repository' "${chart_dir}/Chart.yaml")
}

mirror_chart_images() { # chart_dir stage
  local chart_dir="$1" stage="$2"
  local rendered="${stage}/rendered.yaml"

  # Stage the chart with its dependencies so helm template can render it,
  # then collect every image reference that points at our mirror.
  cp -a "${chart_dir}" "${stage}/chart"
  mkdir -p "${stage}/chart/charts"
  cp "${stage}"/tgz/*.tgz "${stage}/chart/charts/" 2>/dev/null || true
  helm template mirror-probe "${stage}/chart" -n mirror-probe > "${rendered}"

  local mysql_repo mysql_version
  mapfile -t images < <(
    {
      # everything rendered as image: <our-mirror>/...  (digests dropped: tags
      # are copied digest-preserving anyway)
      yq -N -r '.. | select(has("image")) | .image' "${rendered}" 2>/dev/null \
        | grep "^${GAR_MIRROR}/" | sed 's/@sha256:.*//' || true
      # MySQL server/router/sidecar are pulled BY the operator, not rendered as
      # pods: derive them from the InnoDBCluster version + operator default repo
      mysql_repo="$(yq -N -r 'select(.kind == "Deployment") | .spec.template.spec.containers[].env[]? | select(.name == "MYSQL_OPERATOR_DEFAULT_REPOSITORY") | .value' "${rendered}" | head -1)"
      mysql_version="$(yq -N -r 'select(.kind == "InnoDBCluster") | .spec.version' "${rendered}" | head -1)"
      if [[ -n "${mysql_repo}" && -n "${mysql_version}" && "${mysql_version}" != "null" ]]; then
        echo "${mysql_repo}/community-server:${mysql_version}"
        echo "${mysql_repo}/community-router:${mysql_version}"
      fi
    } | sort -u
  )

  if [[ ${#images[@]} -eq 0 ]]; then
    echo "NOTE no rendered images point at ${GAR_MIRROR} — values.yaml not migrated yet, skipping images"
    return
  fi

  local dst rel top src_host src
  for dst in "${images[@]}"; do
    rel="${dst#"${GAR_MIRROR}"/}"               # e.g. mysql/community-server:8.0.45
    top="${rel%%/*}"                            # e.g. mysql
    src_host="${UPSTREAM_REGISTRY[${top}]:-}"
    [[ -n "${src_host}" ]] || { echo "ERR  no upstream registry mapped for '${top}' — add it to UPSTREAM_REGISTRY" >&2; exit 1; }
    src="${src_host}/${rel}"
    if image_exists "${dst}"; then
      echo "OK   image ${rel} already in GAR"
      continue
    fi
    echo "COPY ${src} -> ${dst}"
    copy_image "${src}" "${dst}"
  done
}

for chart_dir in "${CHART_DIRS[@]}"; do
  chart_dir="$(cd "${chart_dir}" && pwd)"
  stage="$(mktemp -d)"
  trap 'rm -rf "${stage}"' EXIT
  echo "=== ${chart_dir#"${REPO_ROOT}"/} ==="
  echo "==> Charts (versions from Chart.yaml)"
  mirror_chart_deps "${chart_dir}" "${stage}"
  echo "==> Images (tags from rendered chart)"
  mirror_chart_images "${chart_dir}" "${stage}"
  rm -rf "${stage}"
done

echo "Done."
