#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/package-chart-release-local.sh [chart-path]

Replicates the chart-releaser packaging step used by .github/workflows/release.yaml
without uploading releases or updating the Helm index.

Environment:
  CR_VERSION       chart-releaser version to use (default: v1.5.0)
  CR_CONFIG        chart-releaser config path (default: .github/ci/cr.yaml)
  CR_PACKAGE_PATH  output directory (default: /tmp/helm-charts-cr-packages)
  CR_BIN           use this chart-releaser binary instead of downloading one
EOF
}

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

chart="${1:-charts/clustercontrol}"
cr_version="${CR_VERSION:-v1.5.0}"
cr_config="${CR_CONFIG:-.github/ci/cr.yaml}"
package_path="${CR_PACKAGE_PATH:-/tmp/helm-charts-cr-packages}"

if [[ ! -f "$chart/Chart.yaml" ]]; then
  echo "ERROR: chart path '$chart' does not contain Chart.yaml" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$cr_config" ]]; then
  echo "ERROR: chart-releaser config '$cr_config' does not exist" >&2
  exit 1
fi

download_cr() {
  local version="$1"
  local os arch tool_dir archive url

  os="$(uname | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "ERROR: unsupported architecture '$arch'" >&2
      exit 1
      ;;
  esac

  tool_dir="${TMPDIR:-/tmp}/helm-charts-cr/${version}/${os}-${arch}"
  mkdir -p "$tool_dir"

  if [[ ! -x "$tool_dir/cr" ]]; then
    archive="$tool_dir/chart-releaser.tar.gz"
    url="https://github.com/helm/chart-releaser/releases/download/${version}/chart-releaser_${version#v}_${os}_${arch}.tar.gz"
    echo "Downloading chart-releaser ${version} for ${os}/${arch}..." >&2
    curl -fsSL "$url" -o "$archive"
    tar -xzf "$archive" -C "$tool_dir" cr
    rm -f "$archive"
  fi

  printf '%s\n' "$tool_dir/cr"
}

if [[ -n "${CR_BIN:-}" ]]; then
  cr_bin="$CR_BIN"
elif command -v cr >/dev/null 2>&1; then
  cr_bin="$(command -v cr)"
else
  cr_bin="$(download_cr "$cr_version")"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/helm-chart-package.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

chart_copy="$tmp_dir/$(basename "$chart")"
cp -a "$chart" "$chart_copy"

rm -rf "$package_path"
mkdir -p "$package_path"

echo "Using chart-releaser: $("$cr_bin" version | head -n 1)"
echo "Packaging chart copy: $chart_copy"
echo "Output directory: $package_path"

"$cr_bin" package "$chart_copy" \
  --config "$cr_config" \
  --package-path "$package_path"

echo
echo "Built packages:"
find "$package_path" -maxdepth 1 -type f -name '*.tgz' -print | sort
