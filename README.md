# Gitea runner images for air-gapped hosts

Builds one file, `gitea-offline-X.Y.Z.tar`, holding everything a Docker host
with no internet access needs to run Gitea Actions jobs: the job images, the
`gitea-runner` controller, mirrors of the common `actions/*` repositories, and
an installer that also handles upgrades.

The design goal is that you burn it once and don't come back for something
that was missing:

- **One file per release.** Images, actions, installer, docs and checksums
  are in a single archive. Every image goes into one `docker save`, so layers
  shared through `runner-base` are stored once.
- **Actions work offline.** `uses: actions/checkout@v4` (and `cache`,
  `upload-artifact`, `download-artifact`, `setup-python`, `setup-node`,
  `github-script`) are pushed into your Gitea with every tag, and the runner
  is configured to fetch them there.
- **No download at job time.** `setup-node`/`setup-python` find the bundled
  Node.js 22 and Python 3.11 in the tool cache, Corepack has pnpm and Yarn
  cached, and `pip install` works without a venv.
- **Fixes without a reburn.** Package registry mirrors (`job.env`), internal
  CA certificates (`ca-certificates/`), extra labels, Docker access for jobs
  and network attachment are all settings on the target host.
- **Painless upgrades.** Run the new bundle's installer. It keeps your
  settings and registration, updates the labels, and can prune old images.
- **Tested air-gapped before release.** CI installs every bundle against a
  throwaway Gitea with container internet access firewalled off, then runs
  [`tests/airgap`](tests/airgap/.github/workflows/airgap.yml) on every label.
  A bundle that needs the internet fails the release.

Installation, upgrades and configuration on the target host are covered in
[`offline/README.md`](offline/README.md), which also ships inside the bundle.

## Images

| `runs-on:` | Image | Contents |
| --- | --- | --- |
| `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `linux` | `runner-base` | Debian 12, Node.js 22, Python 3, git, Git LFS, Docker CLI with Buildx and Compose, jq, curl, wget, rsync, make, zip/xz/zstd, passwordless sudo |
| `python-3.11` | `runner-python311` | Base plus Python 3.11 with headers, a runner-owned environment on `PATH`, pytest, build |
| `cpp` | `runner-cpp` | Base plus GCC 12, Clang/LLD 14, CMake, Ninja, Meson, Autotools, ccache, GDB, Valgrind |
| `dotnet-8` | `runner-dotnet8` | Base plus the .NET 8 SDK |
| `node-22` | `runner-node22` | Base plus npm, pnpm and Yarn (classic and stable) |

All images are linux/amd64 and run steps as the unprivileged `runner` user.
Toolchain major versions are fixed per image. Dependabot proposes only minor
and patch updates; a new major version gets a new image and label.

## Releasing

Push a `vX.Y.Z` tag. The [release workflow](.github/workflows/release.yml)
builds and smoke-tests every image (smoke tests run with `--network none`),
packages the bundle, runs the air-gap test, and attaches these to the GitHub
Release:

- `gitea-offline-X.Y.Z.tar`: the file to burn.
- `SHA256SUMS`: checksum of the above.
- `manifest.json`: image IDs, digests, labels and action commits.

To rebuild an existing tag, run the workflow manually with that tag.

## Customizing the bundle

- **Job images:** add a Dockerfile under `images/` that starts
  `FROM ${BASE_IMAGE}`, add an entry with its labels to
  [`images.json`](images.json), and add a smoke test to
  [`scripts/smoke-image.sh`](scripts/smoke-image.sh).
- **Actions, controller and service images:** edit
  [`bundle.json`](bundle.json). `actions` lists GitHub repositories to mirror,
  and `extra_images` lists additional images to include, such as
  `postgres:16` for service containers.

## Building locally

You need Docker with Buildx, Bash, git, jq, Python 3 with PyYAML, gzip and
OpenSSL.

```sh
./scripts/validate.sh
./scripts/build-image.sh runner-python311 local   # builds runner-base first if needed
./scripts/release.sh 1.2.3                        # every image, then dist/gitea-offline-1.2.3.tar
./scripts/test-bundle.sh dist/gitea-offline-1.2.3.tar
AIRGAP=1 ./scripts/test-bundle.sh dist/gitea-offline-1.2.3.tar   # with egress blocked; needs sudo and iptables
```

`test-bundle.sh` uses host port 3000 and the Compose project name
`gitea-runner`, so don't run it on a machine that already runs the offline
runner.

## CI safety

Pull requests and releases run on GitHub-hosted runners. Don't expose
self-hosted runners to pull-request code from a public repository: a
contributor can change a workflow's runner label in their proposed commit.

## License

[MIT](LICENSE)
