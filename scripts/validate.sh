#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

jq -e '
  length > 0
  and (([.[].name] | length) == ([.[].name] | unique | length))
  and all(.[].name; test("^runner-[a-z0-9]+$"))
  and all(.[].dockerfile; startswith("images/") and endswith("/Dockerfile"))
  and all(.[]; (.labels | type == "array" and length > 0))
  and (([.[].labels[]] | length) == ([.[].labels[]] | unique | length))
  and any(.[]; .name == "runner-base" and .depends_on == null)
' "$repo_root/images.json" >/dev/null || { echo 'images.json is invalid.' >&2; exit 1; }

jq -e '
  (.controller | type == "string" and length > 0)
  and (.extra_images | type == "array")
  and all(.actions[]; test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))
' "$repo_root/bundle.json" >/dev/null || { echo 'bundle.json is invalid.' >&2; exit 1; }

while IFS= read -r file; do
  test -f "$repo_root/$file" || { echo "Missing $file" >&2; exit 1; }
done < <(jq -r '.[].dockerfile' "$repo_root/images.json")

while IFS= read -r file; do
  bash -n "$file"
done < <(find "$repo_root/scripts" "$repo_root/offline" -type f -name '*.sh' -print | sort)
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning --external-sources --source-path="$repo_root" "$repo_root"/scripts/*.sh "$repo_root"/offline/*.sh
fi
if command -v pwsh >/dev/null 2>&1; then
  PS1_FILE="$repo_root/offline/install.ps1" pwsh -NoProfile -NonInteractive -Command '
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($env:PS1_FILE, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { $errors | ForEach-Object { Write-Error $_.ToString() }; exit 1 }'
fi

if grep -rnIiE 'sasmn|koda|10\.[0-9]+\.[0-9]+\.[0-9]+|olympus|internal registry' "$repo_root" \
  --exclude-dir=.git --exclude-dir=dist --exclude=validate.sh; then
  echo 'Public-safety check found forbidden private or work-specific terminology.' >&2
  exit 1
fi

python3 - "$repo_root" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
paths = [*sorted((root / ".github" / "workflows").glob("*.yml")), *sorted((root / "examples").glob("*.yml")),
         root / "tests/airgap/.github/workflows/airgap.yml", root / "offline/compose.yaml", root / "offline/config.yaml"]
for path in paths:
    with path.open(encoding="utf-8") as stream:
        yaml.safe_load(stream)
    print(f"valid YAML: {path.relative_to(root)}")
PY

echo 'Repository validation passed.'
