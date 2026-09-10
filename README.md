# Gitea runner images

Reusable Docker job images for Gitea Actions and `act_runner`. Release assets are
ordinary Docker archives, so they can be downloaded in a browser, moved to an
offline machine and imported without access to a container registry.

## Images

| Image | Contents |
| --- | --- |
| `runner-base` | Debian 12, Node.js 22 action runtime, Git, Git LFS, SSH, curl, jq, archive tools and passwordless sudo |
| `runner-python311` | Base plus Python 3.11, pip, development headers and venv |
| `runner-cpp` | Base plus GCC/G++ 12, CMake 3, Ninja 1, GDB and pkg-config |
| `runner-dotnet8` | Base plus the .NET 8 SDK |
| `runner-node22` | Base plus Node.js 22, npm 10 and Corepack |

Specialized images inherit `runner-base`, and all images run job steps as the
unprivileged `runner` user. Major toolchain versions remain stable within a
repository major release; patch versions follow the upstream Debian, Node and
.NET image updates.

## Versioning and releases

Tags use semantic versions such as `v1.0.0`. A version tag builds and smoke-tests
all images, creates both `.tar` and `.tar.zst` exports, writes `manifest.json` and
`SHA256SUMS`, creates an optional compressed all-images bundle, and attaches the
files directly to the matching GitHub Release.

Download the files from the repository's **Releases** page. Verify them before
moving or importing them:

```sh
sha256sum --check SHA256SUMS
docker load --input runner-python311-1.0.0.tar
```

For a compressed archive:

```sh
zstd --decompress --stdout runner-python311-1.0.0.tar.zst | docker load
```

The loaded image is tagged `runner-python311:1.0.0`. The all-images bundle
contains every compressed image archive, a manifest and its own checksums.

## Build locally

Docker, Bash, Git, jq, ripgrep, Python 3 with PyYAML, and zstd are required.

```sh
./scripts/validate.sh
./scripts/build-image.sh runner-python311 local
./scripts/smoke-image.sh runner-python311 local
```

Build the complete release payload locally with:

```sh
./scripts/release.sh 1.0.0
```

## Gitea `act_runner` labels

Import the desired images on the Docker host used by `act_runner`, then register
labels that map workflow names to those local Docker images:

```sh
./act_runner register --no-interactive \
  --instance https://gitea.example.com \
  --token YOUR_REGISTRATION_TOKEN \
  --labels "ubuntu-latest:docker://runner-base:1.0.0,python-3.11:docker://runner-python311:1.0.0,cpp:docker://runner-cpp:1.0.0,dotnet-8:docker://runner-dotnet8:1.0.0,node-22:docker://runner-node22:1.0.0"
```

Use the corresponding label in a workflow, for example `runs-on: python-3.11`.
Small complete examples are available in [`examples/`](examples/):

- [Python](examples/python.yml)
- [C++](examples/cpp.yml)
- [.NET](examples/dotnet.yml)
- [Node.js](examples/node.yml)

## CI safety

Pull requests and releases use GitHub-hosted runners. Public repositories should
not expose self-hosted runners to pull-request code; a contributor can change a
workflow's runner label in the proposed commit. Use a separate trusted private
dispatcher if release builds must run on private infrastructure.

## License

[MIT](LICENSE)
