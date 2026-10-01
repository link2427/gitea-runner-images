#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
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
done < <(all_images)

DIST_DIR="$dist" "$repo_root/scripts/package-offline.sh" "$version"
