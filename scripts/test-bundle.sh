#!/usr/bin/env bash
# End-to-end test of an offline bundle, the way it is used on an air-gapped
# host: start a throwaway Gitea, run the bundle's installer, push
# tests/airgap and require every job in its workflow to pass.
#
#   scripts/test-bundle.sh dist/gitea-offline-X.Y.Z.tar
#
# With AIRGAP=1 (CI, needs sudo and iptables) every container loses internet
# access before the installer runs, so anything the bundle forgot to include
# fails the test instead of failing on the target host.
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

archive="$(realpath "${1:?usage: test-bundle.sh dist/gitea-offline-X.Y.Z.tar}")"
gitea_image="${GITEA_IMAGE:-docker.io/gitea/gitea:1}"
port="${GITEA_PORT:-3000}"
work="$(mktemp -d)"
gitea=airgap-test-gitea
admin=airgap-admin
password="$(openssl rand -hex 16)"

cleanup() {
  local status=$?
  if ((status != 0)) && [[ -d "$work/install" ]]; then
    (cd "$work/install" && docker compose logs --tail 100 runner) || true
  fi
  (cd "$work/install" 2>/dev/null && docker compose down --volumes --remove-orphans >/dev/null 2>&1) || true
  docker ps -aq --filter name=GITEA-ACTIONS | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker rm -f "$gitea" >/dev/null 2>&1 || true
  docker volume rm gitea-runner-ca >/dev/null 2>&1 || true
  if [[ "${AIRGAP:-0}" == 1 ]]; then
    sudo iptables -D DOCKER-USER -j AIRGAP-TEST 2>/dev/null || true
    sudo iptables -F AIRGAP-TEST 2>/dev/null || true
    sudo iptables -X AIRGAP-TEST 2>/dev/null || true
  fi
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT

api() {
  curl --silent --show-error --fail --header "Authorization: token $token" \
    --header 'Content-Type: application/json' "$@"
}

echo "==> Starting Gitea"
gateway="$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')"
url="http://$gateway:$port"
docker run --detach --name "$gitea" --publish "$port:3000" \
  -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL="$url/" \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__actions__ENABLED=true \
  "$gitea_image" >/dev/null
for _ in $(seq 1 60); do
  curl --silent --fail "http://127.0.0.1:$port/api/healthz" >/dev/null && break
  sleep 1
done
docker exec -u git "$gitea" gitea admin user create --admin --username "$admin" \
  --password "$password" --email admin@example.invalid --must-change-password=false >/dev/null
token="$(curl --silent --fail -u "$admin:$password" -H 'Content-Type: application/json' \
  -d '{"name":"airgap-test","scopes":["all"]}' "http://127.0.0.1:$port/api/v1/users/$admin/tokens" | jq -r .sha1)"
registration="$(docker exec -u git "$gitea" gitea actions generate-runner-token)"

if [[ "${AIRGAP:-0}" == 1 ]]; then
  echo "==> Cutting containers off from the internet"
  gitea_ip="$(docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' "$gitea")"
  sudo iptables -N AIRGAP-TEST
  sudo iptables -A AIRGAP-TEST -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  sudo iptables -A AIRGAP-TEST -d "$gitea_ip" -j ACCEPT
  sudo iptables -A AIRGAP-TEST -j DROP
  sudo iptables -I DOCKER-USER -j AIRGAP-TEST
  if docker run --rm --entrypoint wget "$gitea_image" -q -T 10 -O /dev/null https://github.com 2>/dev/null; then
    echo "Containers can still reach github.com; the air gap is not in place." >&2
    exit 1
  fi
fi

echo "==> Installing the bundle"
tar -xf "$archive" -C "$work"
bundle="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'gitea-offline-*')"
mkdir -p "$work/install/ca-certificates"
openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -days 1 \
  -subj '/CN=Air gap test internal CA' -out "$work/install/ca-certificates/test-ca.crt" 2>/dev/null
printf 'SITE_SETTING=from-job-env\n' > "$work/install/job.env"
GITEA_INSTANCE_URL="$url" \
GITEA_RUNNER_REGISTRATION_TOKEN="$registration" \
GITEA_ACTIONS_TOKEN="$token" \
  "$bundle/install.sh" --dir "$work/install"

echo "==> Checking that a second run (an upgrade) is clean"
"$bundle/install.sh" --dir "$work/install"

echo "==> Running tests/airgap"
api --data '{"name":"airgap"}' "http://127.0.0.1:$port/api/v1/user/repos" >/dev/null
cp -r "$repo_root/tests/airgap" "$work/repo"
cp "$work/install/ca-certificates/test-ca.crt" "$work/repo/test-ca.crt"
git -C "$work/repo" init --quiet --initial-branch main
git -C "$work/repo" add --all
git -C "$work/repo" -c user.name=test -c user.email=test@example.invalid commit --quiet -m test
git -C "$work/repo" -c http.extraHeader="Authorization: token $token" \
  push --quiet "http://127.0.0.1:$port/$admin/airgap.git" main

runs="http://127.0.0.1:$port/api/v1/repos/$admin/airgap/actions"
status=
for _ in $(seq 1 180); do
  status="$(api "$runs/runs" | jq -r '.workflow_runs[0] | "\(.status) \(.conclusion)"' 2>/dev/null || true)"
  [[ "$status" == completed* ]] && break
  sleep 5
done

failed=0
while read -r id name conclusion; do
  echo "--- job $name: $conclusion"
  if [[ "$conclusion" != success ]]; then
    failed=1
    api "$runs/jobs/$id/logs" | tail -n 60
  fi
done < <(api "$runs/jobs" | jq -r '.jobs[] | "\(.id) \(.name) \(.conclusion)"')

for repo in $(api "http://127.0.0.1:$port/api/v1/orgs/actions/repos?limit=50" | jq -r '.[].full_name'); do
  if [[ "$(api "http://127.0.0.1:$port/api/v1/repos/$repo/actions/runs" | jq '.total_count')" != 0 ]]; then
    echo "Imported action $repo triggered its own workflows" >&2
    failed=1
  fi
done

if [[ "$status" != "completed success" || "$failed" != 0 ]]; then
  echo "Air-gap test FAILED (run: ${status:-none})" >&2
  exit 1
fi
echo "Air-gap test passed"
