#!/usr/bin/env bash
# Push the bundled action repositories into Gitea so that
# `uses: actions/checkout@v4` resolves inside the air gap.
#
# The installer runs this inside the bundled runner-base image, so the host
# needs neither git nor curl. Inputs (environment):
#   GITEA_INSTANCE_URL   e.g. http://gitea.example.internal:3000
#   GITEA_ACTIONS_TOKEN  token with write:organization and write:repository
#   ACTIONS_DIR          directory holding actions.json and *.bundle files
set -Eeuo pipefail

url="${GITEA_INSTANCE_URL:?GITEA_INSTANCE_URL is required}"
url="${url%/}"
actions_dir="${ACTIONS_DIR:-/bundle/actions}"
: "${GITEA_ACTIONS_TOKEN:?GITEA_ACTIONS_TOKEN is required}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
# Keep the token out of process arguments.
printf 'Authorization: token %s\n' "$GITEA_ACTIONS_TOKEN" > "$work/auth-header"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.extraHeader
export GIT_CONFIG_VALUE_0="Authorization: token $GITEA_ACTIONS_TOKEN"
export GIT_TERMINAL_PROMPT=0

# api METHOD PATH [JSON] -> prints body, returns 0 for 2xx, 1 otherwise
api() {
  local status
  status="$(curl --silent --show-error --output "$work/body" --write-out '%{http_code}' \
    --header "@$work/auth-header" --header 'Content-Type: application/json' \
    --request "$1" ${3:+--data "$3"} "$url/api/v1$2")"
  cat "$work/body"
  [[ "$status" == 2* ]]
}

if ! api GET /user >/dev/null; then
  echo "Cannot authenticate to $url/api/v1 with the given token." >&2
  exit 1
fi

declare -A owners=()
count="$(jq length "$actions_dir/actions.json")"
for ((i = 0; i < count; i++)); do
  repo="$(jq -r ".[$i].repo" "$actions_dir/actions.json")"
  file="$(jq -r ".[$i].file" "$actions_dir/actions.json")"
  branch="$(jq -r ".[$i].default_branch" "$actions_dir/actions.json")"
  owner="${repo%%/*}"
  name="${repo#*/}"

  if [[ -z "${owners[$owner]:-}" ]]; then
    if ! api GET "/users/$owner" >/dev/null; then
      echo "Creating organization $owner"
      api POST /orgs "$(jq -nc --arg o "$owner" '{username: $o, visibility: "public"}')" >/dev/null \
        || { echo "Failed to create organization $owner: $(cat "$work/body")" >&2; exit 1; }
    fi
    owners[$owner]=1
  fi

  if ! api GET "/repos/$owner/$name" >/dev/null; then
    echo "Creating repository $repo"
    api POST "/orgs/$owner/repos" "$(jq -nc --arg n "$name" '{name: $n, private: false}')" >/dev/null \
      || api POST /user/repos "$(jq -nc --arg n "$name" '{name: $n, private: false}')" >/dev/null \
      || { echo "Failed to create repository $repo: $(cat "$work/body")" >&2; exit 1; }
  fi

  # The mirrors carry their upstream CI workflows; without this, every push
  # would queue those workflows on this runner. Also no issues, PRs or wiki.
  api PATCH "/repos/$owner/$name" \
    '{"has_actions": false, "has_issues": false, "has_pull_requests": false, "has_wiki": false, "has_projects": false}' >/dev/null \
    || { echo "Failed to disable Actions on $repo: $(cat "$work/body")" >&2; exit 1; }

  echo "Pushing $repo"
  rm -rf "$work/repo.git"
  git clone --quiet --bare "$actions_dir/$file" "$work/repo.git"
  # Force so that re-imports move floating tags such as v4 to their new commit.
  git -C "$work/repo.git" push --quiet --force "$url/$repo.git" \
    'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
  api PATCH "/repos/$owner/$name" "$(jq -nc --arg b "$branch" '{default_branch: $b}')" >/dev/null || true
done

echo "Imported $count action repositories into $url"
