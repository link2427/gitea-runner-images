#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/lib.sh"

name="${1:?usage: smoke-image.sh IMAGE [VERSION]}"
version="${2:-local}"
image="$name:$version"

case "$name" in
  runner-base)
    docker run --rm "$image" bash -lc '
      test "$(id -un)" = runner
      test "${HOME}" = /home/runner
      git --version
      jq --version
      node --version | grep -Eq "^v22\."
      zstd --version
    '
    ;;
  runner-python311)
    docker run --rm "$image" bash -lc '
      python --version 2>&1 | grep -Eq "^Python 3\.11\."
      python -m venv /tmp/venv
      /tmp/venv/bin/python -m pip --version
      /tmp/venv/bin/python -c "print(sum([1, 2, 3]))"
    '
    ;;
  runner-cpp)
    docker run --rm "$image" bash -lc '
      printf "#include <iostream>\nint main(){std::cout << 42;}\n" > /tmp/main.cpp
      g++ -std=c++20 -Wall -Wextra -Werror /tmp/main.cpp -o /tmp/smoke
      test "$(/tmp/smoke)" = 42
      cmake --version
      ninja --version
    '
    ;;
  runner-dotnet8)
    docker run --rm "$image" bash -lc '
      dotnet --version | grep -Eq "^8\."
      mkdir /tmp/smoke && cd /tmp/smoke
      dotnet new console --no-restore
      dotnet run
    '
    ;;
  runner-node22)
    docker run --rm "$image" bash -lc '
      node --version | grep -Eq "^v22\."
      npm --version
      corepack --version
      test "$(node -p "6 * 7")" = 42
    '
    ;;
  *)
    echo "No smoke test for $name" >&2
    exit 2
    ;;
esac
