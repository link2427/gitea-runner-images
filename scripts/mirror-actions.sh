#!/usr/bin/env bash
# Mirror the action repositories listed in bundle.json into git bundles that
# the offline installer pushes into the air-gapped Gitea instance.
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

out="${1:?usage: mirror-actions.sh OUTPUT_DIR}"
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

records=()
while IFS= read -r repo; do
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid action repository: $repo" >&2; exit 2; }
  echo "Mirroring $repo"
  clone="$work/${repo//\//__}.git"
  git clone --quiet --bare "https://github.com/$repo.git" "$clone"
  default_branch="$(git -C "$clone" symbolic-ref --short HEAD)"
  file="${repo//\//__}.bundle"
  # The default branch plus every tag covers `uses: owner/repo@vN`,
  # `@vN.N.N` and `@<sha>` for any released commit.
  git -C "$clone" bundle create --quiet "$out/$file" "refs/heads/$default_branch" --tags
  git bundle verify --quiet "$out/$file"
  records+=("$(jq -nc \
    --arg repo "$repo" \
    --arg file "$file" \
    --arg branch "$default_branch" \
    --arg commit "$(git -C "$clone" rev-parse HEAD)" \
    --argjson tags "$(git -C "$clone" tag | wc -l)" \
    '{repo: $repo, file: $file, default_branch: $branch, commit: $commit, tags: $tags}')")
done < <(bundle_field '.actions[]')

printf '%s\n' "${records[@]}" | jq -s '.' > "$out/actions.json"
