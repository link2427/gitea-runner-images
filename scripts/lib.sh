#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

image_exists() {
  jq -e --arg name "$1" 'any(.[]; .name == $name)' "$repo_root/images.json" >/dev/null
}

image_field() {
  local name="$1"
  local field="$2"
  jq -r --arg name "$name" --arg field "$field" '.[] | select(.name == $name) | .[$field] // empty' "$repo_root/images.json"
}

all_images() {
  jq -r '.[].name' "$repo_root/images.json"
}
