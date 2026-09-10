#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/lib.sh"

base="${1:?usage: changed-images.sh BASE_SHA [HEAD_SHA]}"
head="${2:-HEAD}"

if [[ "$base" =~ ^0+$ ]] || ! git -C "$repo_root" cat-file -e "$base^{commit}" 2>/dev/null; then
  all_images | jq -Rsc 'split("\n") | map(select(length > 0))'
  exit 0
fi

mapfile -t changed < <(git -C "$repo_root" diff --name-only "$base" "$head")

declare -A selected=()
for path in "${changed[@]}"; do
  case "$path" in
    images/base/*|images.json|scripts/*)
      while IFS= read -r name; do selected["$name"]=1; done < <(all_images)
      ;;
    images/python311/*) selected[runner-python311]=1 ;;
    images/cpp/*) selected[runner-cpp]=1 ;;
    images/dotnet8/*) selected[runner-dotnet8]=1 ;;
    images/node22/*) selected[runner-node22]=1 ;;
  esac
done

if ((${#selected[@]} == 0)); then
  printf '[]\n'
else
  printf '%s\n' "${!selected[@]}" | sort | jq -Rsc 'split("\n") | map(select(length > 0))'
fi
