# Maintainer scripts

Internal tooling for the chart dependency mirror. Not shipped with any chart —
end-user docs live in each chart's own README.

## Background

Third-party chart dependencies and the container images they pull are mirrored
("cached") in our public Google Artifact Registry, because upstream registries
have repeatedly pruned released artifacts we depend on (Oracle removed the
`mysql-operator` 2.0.21 chart *and* its operator images; see
[CLUS-7736](https://severalnines.atlassian.net/browse/CLUS-7736)):

| What | Where |
|------|-------|
| Charts (OCI) | `oci://europe-docker.pkg.dev/severalnines-public/clustercontrol/helm-charts/<name>:<version>` |
| Images | `europe-docker.pkg.dev/severalnines-public/clustercontrol/mirror/<upstream-path>:<tag>` |

Only released artifact binaries are hosted — no chart sources are forked.
The repo is public: pulls (helm, kubelet, CI) are anonymous; only *pushing* to
the mirror needs credentials. Currently only `charts/clustercontrol` uses the
mirror.

## mirror-to-gar.sh — seed / update the mirror

```bash
./scripts/mirror-to-gar.sh                  # mirror everything the chart needs
./scripts/mirror-to-gar.sh --dry-run        # show what would be mirrored
./scripts/mirror-to-gar.sh --seed-from DIR  # use local chart tgz for versions pruned upstream
```

**There is no version list in the script.** The chart is the single source of
truth: dependency versions are read from `Chart.yaml`, image tags from
rendering the chart with `helm template` (which resolves subchart defaults and
`values.yaml` overrides; the MySQL server/router tag is read from the rendered
InnoDBCluster resource because the operator pulls those at runtime).

The script is idempotent — artifacts already in GAR are skipped, so the mirror
keeps every version forever and re-runs are cheap (~1 min of existence
checks). Interrupted image copies resume at the blob level on retry.

The two maps at the top of the script (`UPSTREAM_CHART_REPO`,
`UPSTREAM_REGISTRY`) are *not* version info — they only map names back to
upstream sources, and only change when a new dependency or registry is
introduced. `CHART_DIRS` lists the charts to process; extending the mirror to
another chart (ccxdeps, observability, …) is one line there plus any new map
entries.

### Bumping a dependency version

1. Edit the version in `charts/clustercontrol/Chart.yaml` (and any image tag
   overrides in `values.yaml`, if you pin tags there).
2. `./scripts/mirror-to-gar.sh` — pulls the new chart from upstream, pushes it
   to GAR, and copies whatever new images the rendered chart references.
3. `./scripts/build-charts.sh` to verify packaging, then commit and open a PR.

### Prerequisites

- `helm` >= 3.8, `yq` v4, and `crane`
  ([go-containerregistry](https://github.com/google/go-containerregistry/releases);
  `skopeo` also works) — crane/skopeo only for image copies.
- Push access: a service account with **Artifact Registry Writer** on
  `severalnines-public/clustercontrol`, then:

  ```bash
  ACCOUNT=<sa-with-writer-role>   # e.g. cc-dev-buildbot@severalnines-public.iam.gserviceaccount.com
  gcloud auth print-access-token "$ACCOUNT" | helm registry login -u oauth2accesstoken --password-stdin europe-docker.pkg.dev
  gcloud auth print-access-token "$ACCOUNT" | crane auth login europe-docker.pkg.dev -u oauth2accesstoken --password-stdin
  ```

  Note: access tokens expire after ~1 h; re-login for long seeding sessions.
  If your `~/.docker/config.json` routes `europe-docker.pkg.dev` through the
  `gcloud` credential helper, crane will use the *active* gcloud account —
  either switch it, or point `DOCKER_CONFIG` at a clean dir before
  `crane auth login`.

- **Network matters for the first seed**: the full image set is ~1 GB. Run it
  from a machine with good upstream bandwidth (CI runner, cloud VM) — over a
  weak uplink the registry uploads stall and retry painfully. Incremental
  updates later only transfer new layers.

### When upstream has already pruned the version

`helm pull` from upstream fails for a pruned chart version. Recover the
tarball from git history (the versions we shipped before this mirror existed
are tracked there) and seed from a local dir:

```bash
mkdir seed
git show <ref>:charts/clustercontrol/charts/mysql-operator-2.0.21.tgz > seed/mysql-operator-2.0.21.tgz
./scripts/mirror-to-gar.sh --seed-from seed
```

## build-charts.sh — pre-PR build check

Packages charts exactly the way CI does, so you catch dependency-resolution
failures before opening a PR:

```bash
./scripts/build-charts.sh                  # default: clustercontrol
./scripts/build-charts.sh ccx observability
```

Runs, per chart:

1. `helm lint` — what `.github/workflows/lint.yaml` runs on PRs.
2. `cr package` — what `.github/workflows/release.yaml` runs via
   helm/chart-releaser-action. **`cr` re-downloads dependencies from the
   `repository:` field in `Chart.yaml`** (it ignores anything vendored in
   `charts/`), so this verifies the GAR mirror serves every dependency.
3. `helm package --dependency-update` — what
   `.github/workflows/relese-single.yaml` runs on manual dispatch.

Output lands in `.cr-release-packages/` (gitignored, same dir CI uses).
Installs `cr` v1.7.0 to `~/.cache/chart-releaser/` if not on PATH.
