#!/usr/bin/env bash
# Assemble the single offline bundle from job images that build-image.sh has
# already built and tagged NAME:VERSION.
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

version="${1:?usage: package-offline.sh X.Y.Z}"
dist="${DIST_DIR:-$repo_root/dist}"
platform="${PLATFORM:-linux/amd64}"
revision="${REVISION:-$(git -C "$repo_root" rev-parse --verify HEAD 2>/dev/null || printf development)}"
bundle_name="gitea-offline-$version"
stage="$dist/$bundle_name"
max_asset_bytes=$((2 * 1024 * 1024 * 1024 - 1))

rm -rf "$stage"
mkdir -p "$stage/images" "$stage/actions"

mapfile -t job_images < <(all_images | sed "s/\$/:$version/")
controller="$(bundle_field '.controller')"
mapfile -t extra_images < <(bundle_field '.extra_images[]')

# PULL_IMAGES=0 reuses local copies, e.g. when re-packaging after a registry outage.
if [[ "${PULL_IMAGES:-1}" != 0 ]]; then
  for image in "$controller" "${extra_images[@]}"; do
    docker pull --quiet --platform "$platform" "$image" >/dev/null
  done
fi

# One archive for everything: docker save stores each shared layer once, so
# the base image is not repeated for every toolchain image. gzip is the one
# compression every docker and podman version can load directly.
all_tags=("${job_images[@]}" "$controller" "${extra_images[@]}")
echo "Exporting ${#all_tags[@]} images"
compressor=(gzip -6)
if command -v pigz >/dev/null 2>&1; then compressor=(pigz -6); fi
docker save "${all_tags[@]}" | "${compressor[@]}" > "$stage/images/images.tar.gz"

"$repo_root/scripts/mirror-actions.sh" "$stage/actions"

cp "$repo_root/offline/README.md" "$repo_root/offline/install.sh" "$repo_root/offline/install.ps1" \
  "$repo_root/offline/import-actions.sh" "$stage/"
printf '%s\n' "$version" > "$stage/VERSION"
cp "$repo_root/offline/config.yaml" "$stage/config.yaml.template"
cp "$repo_root/offline/env.example" "$stage/.env.example"
cp "$repo_root/offline/job.env.example" "$stage/job.env.example"
chmod +x "$stage/install.sh" "$stage/import-actions.sh"
sed -e "s|@LABELS@|$(runner_labels "$version")|" \
    -e "s|@CONTROLLER@|$controller|" \
    "$repo_root/offline/compose.yaml" > "$stage/compose.yaml"
cp -r "$repo_root/examples" "$stage/examples"

python3 - "$repo_root" "$stage" "$version" "$revision" "$controller" "${extra_images[@]}" <<'PY'
import json
import pathlib
import subprocess
import sys

root, stage = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
version, revision, controller, extras = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6:]

def inspect(tag):
    record = json.loads(subprocess.check_output(["docker", "image", "inspect", tag], text=True))[0]
    return {
        "tag": tag,
        "image_id": record["Id"],
        "repo_digests": record.get("RepoDigests") or [],
        "os": record["Os"],
        "architecture": record["Architecture"],
        "bytes": record.get("Size"),
    }

job_images = []
for definition in json.loads((root / "images.json").read_text(encoding="utf-8")):
    entry = inspect(f"{definition['name']}:{version}")
    entry.update(name=definition["name"], labels=definition["labels"], toolchains=definition["toolchains"])
    job_images.append(entry)

manifest = {
    "schema_version": 2,
    "version": version,
    "source_revision": revision,
    "job_images": job_images,
    "controller": inspect(controller),
    "extra_images": [inspect(tag) for tag in extras],
    "actions": json.loads((stage / "actions" / "actions.json").read_text(encoding="utf-8")),
}
for image in [*job_images, manifest["controller"], *manifest["extra_images"]]:
    if (image["os"], image["architecture"]) != ("linux", "amd64"):
        sys.exit(f"{image['tag']} is {image['os']}/{image['architecture']}, expected linux/amd64")
(stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

(
  cd "$stage"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum --check --quiet SHA256SUMS
)

# The outer archive is uncompressed (its large members already are) and is a
# plain tar so it extracts with the tar built into Linux and Windows 10+.
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -C "$dist" -cf "$dist/$bundle_name.tar" "$bundle_name"
size="$(stat -c %s "$dist/$bundle_name.tar")"
if ((size > max_asset_bytes)); then
  echo "$bundle_name.tar is $size bytes, over the 2 GiB GitHub release asset limit" >&2
  exit 1
fi
cp "$stage/manifest.json" "$dist/manifest.json"
(cd "$dist" && sha256sum "$bundle_name.tar" manifest.json > SHA256SUMS)
rm -rf "$stage"

echo "Offline bundle written to $dist/$bundle_name.tar ($((size / 1024 / 1024)) MiB)"
