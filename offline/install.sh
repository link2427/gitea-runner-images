#!/usr/bin/env bash
# Install or upgrade the offline Gitea runner from this bundle.
#
#   ./install.sh [--dir DIR] [--skip-actions] [--no-start] [--prune]
#
# Safe to run again: each run verifies the bundle, loads its images, refreshes
# compose.yaml, re-imports the actions and restarts the runner. Site settings
# (.env, config.yaml, job.env, ca-certificates/, data/) are never overwritten.
set -Eeuo pipefail

bundle="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${GITEA_RUNNER_DIR:-/opt/gitea-runner}"
import_actions=1
start=1
prune=0

usage() { sed -n '2,9s/^# \{0,1\}//p' "$0"; }
while (($#)); do
  case "$1" in
    --dir) dir="${2:?--dir needs a path}"; shift 2 ;;
    --dir=*) dir="${1#*=}"; shift ;;
    --skip-actions) import_actions=0; shift ;;
    --no-start) start=0; shift ;;
    --prune) prune=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

env_get() {
  local value
  value="$(sed -n "s/^$1=//p" "$dir/.env" 2>/dev/null | tail -n 1)"
  value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
  printf '%s' "$value"
}

env_set() {
  local tmp="$dir/.env.tmp"
  KEY="$1" VALUE="$2" awk 'BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
    index($0, k "=") == 1 { print k "=" v; done = 1; next } { print }
    END { if (!done) print k "=" v }' "$dir/.env" > "$tmp"
  mv "$tmp" "$dir/.env"
}

render() {
  local escaped
  escaped="$(printf '%s' "$2" | sed -e 's/[|&\\]/\\&/g')"
  sed "s|@GITEA_INSTANCE_URL@|$escaped|g" "$1"
}

version="$(cat "$bundle/VERSION")"
base_image="runner-base:$version"

say "Gitea offline runner bundle $version -> $dir"

command -v docker >/dev/null || die "docker is not installed or not on PATH."
docker info >/dev/null 2>&1 || die "Cannot reach the Docker daemon (are you root or in the docker group?)."
docker compose version >/dev/null 2>&1 || die "The Docker Compose v2 plugin ('docker compose') is required."

say "Verifying bundle checksums"
(cd "$bundle" && sha256sum --check --quiet SHA256SUMS) \
  || die "The bundle is damaged or incomplete. Copy it from the media again."

mkdir -p "$dir/data" "$dir/ca-certificates"
if [[ ! -f "$dir/.env" ]]; then
  cp "$bundle/.env.example" "$dir/.env"
  chmod 600 "$dir/.env"
  for key in GITEA_INSTANCE_URL GITEA_RUNNER_REGISTRATION_TOKEN GITEA_RUNNER_NAME GITEA_ACTIONS_TOKEN; do
    if [[ -n "${!key:-}" ]]; then env_set "$key" "${!key}"; fi
  done
fi

url="$(env_get GITEA_INSTANCE_URL)"
url="${url%/}"
if [[ -z "$url" || "$url" == *gitea.example.internal* ]]; then
  die "Set GITEA_INSTANCE_URL (and GITEA_RUNNER_REGISTRATION_TOKEN for the first install) in $dir/.env, then run this again."
fi
if [[ ! -s "$dir/data/.runner" && -z "$(env_get GITEA_RUNNER_REGISTRATION_TOKEN)" ]]; then
  die "This runner is not registered yet: set GITEA_RUNNER_REGISTRATION_TOKEN in $dir/.env, then run this again."
fi

say "Loading images (several minutes on slow media)"
docker load --input "$bundle/images/images.tar.gz"

say "Writing configuration"
cp "$bundle/compose.yaml" "$dir/compose.yaml"
cp "$bundle/manifest.json" "$dir/manifest.json"
[[ -f "$dir/job.env" ]] || cp "$bundle/job.env.example" "$dir/job.env"
render "$bundle/config.yaml.template" "$url" > "$dir/config.yaml.template.new"
if [[ ! -f "$dir/config.yaml" ]]; then
  cp "$dir/config.yaml.template.new" "$dir/config.yaml"
  echo "Created $dir/config.yaml"
elif [[ -f "$dir/config.yaml.template" ]] && ! cmp -s "$dir/config.yaml.template" "$dir/config.yaml.template.new"; then
  echo "Kept your config.yaml. This bundle changed the recommended settings; merge what you need:"
  diff -u "$dir/config.yaml.template" "$dir/config.yaml.template.new" | sed -n '3,$p' | grep '^[-+]' || true
elif [[ ! -f "$dir/config.yaml.template" ]] && ! cmp -s "$dir/config.yaml" "$dir/config.yaml.template.new"; then
  echo "Kept your config.yaml. Compare it with config.yaml.template for this bundle's recommended settings."
fi
mv "$dir/config.yaml.template.new" "$dir/config.yaml.template"

say "Building the CA trust store for the runner and jobs"
count="$(find "$dir/ca-certificates" -type f -name '*.crt' | wc -l)"
docker volume create gitea-runner-ca >/dev/null
docker run --rm --user root --network none \
  -v gitea-runner-ca:/out \
  -v "$dir/ca-certificates:/usr/local/share/ca-certificates/site:ro" \
  "$base_image" bash -euc 'update-ca-certificates >/dev/null 2>&1; find /out -mindepth 1 -delete; cp -rL /etc/ssl/certs/. /out/'
echo "Trusting the public CAs plus $count site certificate(s) from $dir/ca-certificates"

if ((import_actions)); then
  token="${GITEA_ACTIONS_TOKEN:-$(env_get GITEA_ACTIONS_TOKEN)}"
  if [[ -z "$token" && -t 0 ]]; then
    read -rsp "Gitea access token for importing actions (Enter to skip): " token
    echo
  fi
  if [[ -z "$token" ]]; then
    warn "Skipped importing actions; 'uses: actions/...' steps will fail until you do. Set GITEA_ACTIONS_TOKEN in $dir/.env and run this again."
  else
    say "Importing actions into $url"
    GITEA_ACTIONS_TOKEN="$token" docker run --rm \
      -e GITEA_INSTANCE_URL="$url" -e GITEA_ACTIONS_TOKEN \
      -v "$bundle:/bundle:ro" -v gitea-runner-ca:/etc/ssl/certs:ro \
      "$base_image" bash /bundle/import-actions.sh
  fi
fi

if ((start)); then
  say "Starting the runner"
  (cd "$dir" && docker compose up --detach --remove-orphans)
  for _ in $(seq 1 30); do
    [[ -s "$dir/data/.runner" ]] && break
    sleep 2
  done
  if [[ -s "$dir/data/.runner" ]]; then
    echo "Runner is registered. Check it under Gitea > Settings > Actions > Runners."
  else
    warn "The runner has not registered yet. Inspect: (cd $dir && docker compose logs runner)"
  fi
fi

if ((prune)); then
  say "Removing job images from other bundle versions"
  docker image ls --format '{{.Repository}}:{{.Tag}}' \
    | grep -E '^runner-[a-z0-9]+:' | grep -v ":$version\$" \
    | xargs -r docker image rm || warn "Some old images are still in use and were kept."
fi

printf '%s\n' "$version" > "$dir/VERSION"
say "Installed bundle $version"
