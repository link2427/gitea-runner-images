#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/lib.sh"

version="${1:?usage: release.sh X.Y.Z}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be X.Y.Z, got: $version" >&2
  exit 2
fi

dist="${DIST_DIR:-$repo_root/dist}"
rm -rf "$dist"
mkdir -p "$dist"

while IFS= read -r name; do
  "$repo_root/scripts/build-image.sh" "$name" "$version"
  docker save --output "$dist/$name-$version.tar" "$name:$version"
  zstd --threads=0 --quiet -6 --keep "$dist/$name-$version.tar"
done < <(all_images)

python3 - "$repo_root" "$dist" "$version" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
dist = pathlib.Path(sys.argv[2])
version = sys.argv[3]
definitions = json.loads((root / "images.json").read_text(encoding="utf-8"))
images = []
for definition in definitions:
    name = definition["name"]
    record = json.loads(subprocess.check_output(["docker", "image", "inspect", f"{name}:{version}"], text=True))[0]
    files = []
    for suffix in (".tar", ".tar.zst"):
        path = dist / f"{name}-{version}{suffix}"
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        files.append({"name": path.name, "bytes": path.stat().st_size, "sha256": digest})
    images.append({
        "name": name,
        "tag": f"{name}:{version}",
        "image_id": record["Id"],
        "architecture": record["Architecture"],
        "os": record["Os"],
        "toolchains": definition["toolchains"],
        "files": files,
    })

manifest = {"schema_version": 1, "version": version, "images": images}
(dist / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

bundle_dir="$(mktemp -d)"
trap 'rm -rf "$bundle_dir"' EXIT
cp "$dist"/*.tar.zst "$dist/manifest.json" "$bundle_dir/"
(
  cd "$bundle_dir"
  sha256sum ./*.tar.zst manifest.json > SHA256SUMS
  tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cf - . \
    | zstd --threads=0 --quiet -6 -o "$dist/runner-images-$version.tar.zst"
)

(
  cd "$dist"
  sha256sum ./*.tar ./*.tar.zst manifest.json > SHA256SUMS
  sha256sum --check SHA256SUMS
)

echo "Release artifacts written to $dist"
