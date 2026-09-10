#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/lib.sh"

jq -e '
  length == 5
  and (([.[].name] | length) == ([.[].name] | unique | length))
  and all(.[].name; test("^runner-[a-z0-9]+$"))
  and all(.[].dockerfile; startswith("images/") and endswith("/Dockerfile"))
' "$repo_root/images.json" >/dev/null

while IFS= read -r file; do
  bash -n "$file"
done < <(find "$repo_root/scripts" -type f -name '*.sh' -print | sort)

while IFS= read -r file; do
  test -f "$repo_root/$file"
done < <(jq -r '.[].dockerfile' "$repo_root/images.json")

if rg -n -i 'sasmn|koda|10\.[0-9]+\.[0-9]+\.[0-9]+|olympus|internal registry' \
  "$repo_root" \
  --glob '!scripts/validate.sh' \
  --glob '!.git/**'; then
  echo 'Public-safety check found forbidden private or work-specific terminology.' >&2
  exit 1
fi

python3 - "$repo_root" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for path in sorted((root / ".github" / "workflows").glob("*.yml")):
    with path.open(encoding="utf-8") as stream:
        yaml.safe_load(stream)
    print(f"valid YAML: {path.relative_to(root)}")
PY

echo 'Repository validation passed.'
