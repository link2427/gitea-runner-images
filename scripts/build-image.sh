#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/lib.sh"

name="${1:?usage: build-image.sh IMAGE [VERSION]}"
version="${2:-local}"
revision="${REVISION:-$(git -C "$repo_root" rev-parse --verify HEAD 2>/dev/null || printf development)}"

if ! image_exists "$name"; then
  echo "Unknown image: $name" >&2
  exit 2
fi

dependency="$(image_field "$name" depends_on)"
if [[ -n "$dependency" ]] && ! docker image inspect "$dependency:$version" >/dev/null 2>&1; then
  "$repo_root/scripts/build-image.sh" "$dependency" "$version"
fi

dockerfile="$(image_field "$name" dockerfile)"
args=(
  build
  --file "$repo_root/$dockerfile"
  --tag "$name:$version"
  --build-arg "VERSION=$version"
  --build-arg "REVISION=$revision"
)
if [[ -n "$dependency" ]]; then
  args+=(--build-arg "BASE_IMAGE=$dependency:$version")
fi
args+=("$repo_root")

docker "${args[@]}"
"$repo_root/scripts/smoke-image.sh" "$name" "$version"
