# Offline Gitea runner bundle

Everything needed to run Gitea Actions jobs on a Docker host with no internet
access. Nothing here is downloaded at install or job time.

| Path | Contents |
| --- | --- |
| `images/images.tar.gz` | Every job image, plus the `gitea-runner` controller, in one archive |
| `actions/` | Git mirrors of common actions (`actions/checkout`, `setup-node`, ...) |
| `install.sh`, `install.ps1` | Installer and upgrader for Linux and Windows hosts |
| `manifest.json` | Image IDs, digests, labels and action commits in this bundle |
| `SHA256SUMS` | Checksums the installer verifies before touching anything |
| `examples/` | Small workflows for each toolchain |

## Requirements

- Docker Engine with the Compose v2 plugin (`docker compose`), Linux containers, x86-64.
- A Gitea server with Actions enabled, reachable by URL from this host and
  from containers on it.
- A runner registration token: Gitea > Site Administration (or organization
  or repository settings) > Actions > Runners > Create new runner.
- Optionally, a Gitea access token with the `write:organization` and
  `write:repository` scopes, from an account allowed to create
  organizations. The installer uses it to push the bundled actions into Gitea.

The host needs no git, curl or jq: those steps run inside the bundled images.

## First install

Linux:

```sh
tar -xf gitea-offline-X.Y.Z.tar
cd gitea-offline-X.Y.Z
sudo GITEA_INSTANCE_URL=http://gitea.example.internal:3000 \
     GITEA_RUNNER_REGISTRATION_TOKEN=... \
     GITEA_ACTIONS_TOKEN=... \
     ./install.sh
```

Windows (PowerShell, Docker Desktop with Linux containers):

```powershell
tar -xf gitea-offline-X.Y.Z.tar
cd gitea-offline-X.Y.Z
$env:GITEA_INSTANCE_URL = "http://gitea.example.internal:3000"
$env:GITEA_RUNNER_REGISTRATION_TOKEN = "..."
$env:GITEA_ACTIONS_TOKEN = "..."
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If your organization forbids `-ExecutionPolicy Bypass`, follow "Manual install"
below instead.

The installer keeps its state in `/opt/gitea-runner` (Windows:
`%USERPROFILE%\gitea-runner`); pass `--dir PATH` / `-Dir PATH` to choose
another place. Instead of environment variables you can run it once, fill in
the `.env` it creates there, and run it again.

## Upgrading

Burn the new bundle, then run its installer the same way. No environment
variables are needed after the first install:

```sh
sudo ./install.sh            # add --prune to delete the previous job images
```

Upgrades verify the bundle, load the new images, re-import the actions,
update the runner's labels and restart it. These files belong to you and are
never overwritten:

| File in the install directory | Purpose |
| --- | --- |
| `.env` | Gitea URL, tokens, runner name, extra labels |
| `config.yaml` | Runner settings (capacity, timeouts, Docker options) |
| `job.env` | Environment variables for every job (package mirrors, proxies) |
| `ca-certificates/*.crt` | Extra CAs to trust, e.g. your internal CA |
| `compose.override.yaml` | Optional Docker Compose additions |
| `data/` | Runner registration |

When a bundle ships changed defaults, the installer prints the difference
against `config.yaml.template` instead of replacing your `config.yaml`.

## Workflow labels

| `runs-on:` | Image |
| --- | --- |
| `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `linux` | `runner-base`: Debian 12, Node.js 22, Python 3, git, Docker CLI, common tools |
| `python-3.11` | `runner-python311`: Python 3.11; `pip install` works without a venv; pytest |
| `cpp` | `runner-cpp`: GCC 12, Clang, CMake, Ninja, Meson, Autotools, ccache, GDB, Valgrind |
| `dotnet-8` | `runner-dotnet8`: .NET 8 SDK |
| `node-22` | `runner-node22`: Node.js 22, npm, pnpm, Yarn |

The `ubuntu-*` labels run Debian, so workflows copied from GitHub mostly
work unchanged. Add your own labels with `EXTRA_RUNNER_LABELS` in `.env`.

## Actions

`uses: actions/checkout@v4` normally clones from github.com. The installer
pushes the bundled copies into Gitea (organization `actions`), and
`config.yaml` sets `github_mirror` so the runner fetches them from there.
Every released tag is included, so `@v3`, `@v4`, `@v4.2.2` and so on all work.

`actions/setup-node` with `node-version: 22` and `actions/setup-python` with
`python-version: 3.11` find the preinstalled toolchains and download nothing.
Other versions, and `actions/setup-dotnet`, need the internet: use the
preinstalled `dotnet` directly.

Re-import at any time with `./install.sh --no-start`. If Gitea requires
sign-in to view repositories, the runner cannot clone them anonymously; set
`DEFAULT_ACTIONS_URL = self` under `[actions]` in Gitea's `app.ini` instead.

## Dependencies (pip, npm, NuGet)

Jobs cannot reach public package registries. Gitea's built-in package
registry, or any mirror inside the air gap, works: point the tools at it in
`job.env`, then `docker compose restart` in the install directory.

```sh
PIP_INDEX_URL=http://gitea.example.internal:3000/api/packages/ORG/pypi/simple
NPM_CONFIG_REGISTRY=http://gitea.example.internal:3000/api/packages/ORG/npm/
```

For NuGet, add a `nuget.config` to the repository.

## Internal CA certificates

Copy PEM `.crt` files into `ca-certificates/` in the install directory and
run the installer again. The runner, the action import and every job
container then trust them (git, curl, Python, Node.js and .NET).

## Networking

`GITEA_INSTANCE_URL` must work from inside containers: `localhost` does not.
If Gitea runs as a container on this host, attach the runner and jobs to its
network. Create `compose.override.yaml` in the install directory:

```yaml
services:
  runner:
    networks: [default, gitea]
networks:
  gitea:
    external: true
    name: YOUR_GITEA_NETWORK
```

and set `container.network: YOUR_GITEA_NETWORK` in `config.yaml`.

## Docker inside jobs

The images include the Docker CLI with Buildx and Compose. To let jobs use the
host's Docker daemon, set `container.docker_host: ""` in `config.yaml`. Only
do this for trusted workflows: it grants root on the host.

## Manual install

Use this when scripts are not allowed. From the bundle directory:

1. Verify: `sha256sum -c SHA256SUMS` (PowerShell: compare
   `Get-FileHash -Algorithm SHA256 <file>` against each line).
2. Load: `docker load -i images/images.tar.gz`
3. Create an install directory containing `compose.yaml`, an empty `job.env`,
   a `.env` made from `.env.example`, and a `config.yaml` made from
   `config.yaml.template` with `@GITEA_INSTANCE_URL@` replaced by your URL.
4. `docker volume create gitea-runner-ca`, then fill it:
   `docker run --rm --user root -v gitea-runner-ca:/out runner-base:X.Y.Z sh -c "cp -rL /etc/ssl/certs/. /out/"`
5. Import actions (optional): `docker run --rm -e GITEA_INSTANCE_URL=... -e GITEA_ACTIONS_TOKEN=... -v "<bundle dir>:/bundle:ro" runner-base:X.Y.Z bash /bundle/import-actions.sh`
6. In the install directory: `docker compose up -d`

## Security

The runner controller has access to the Docker socket, which is equivalent to
root on this host. Run trusted workflows only, and keep `.env` and `data/`
private.
