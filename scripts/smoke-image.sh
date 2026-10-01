#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

name="${1:?usage: smoke-image.sh IMAGE [VERSION]}"
version="${2:-local}"
image="$name:$version"

# Every check runs without a network: the images are meant for hosts that
# have none, so anything that silently downloads at job time is a bug.
run() {
  docker run --rm --network none "$image" bash -euo pipefail -c "$1"
}

case "$name" in
  runner-base)
    run '
      test "$(id -un)" = runner
      test "${HOME}" = /home/runner
      git --version
      git lfs version
      jq --version
      python3 --version
      docker --version
      docker buildx version
      docker compose version
      node --version | grep -Eq "^v22\."
      test -f "$RUNNER_TOOL_CACHE/node/$(node -p process.versions.node)/x64.complete"
      test -x "$RUNNER_TOOL_CACHE/node/$(node -p process.versions.node)/x64/bin/node"
      test -f "$RUNNER_TOOL_CACHE/Python/$(python3 -c "import platform; print(platform.python_version())")/x64.complete"
      zstd --version
    '
    ;;
  runner-python311)
    run '
      python --version 2>&1 | grep -Eq "^Python 3\.11\."
      version="$(python -c "import platform; print(platform.python_version())")"
      test -f "$RUNNER_TOOL_CACHE/Python/$version/x64.complete"
      test -x "$RUNNER_TOOL_CACHE/Python/$version/x64/bin/python"
      pip install --no-index --no-build-isolation --quiet --upgrade setuptools
      python -m venv /tmp/venv
      /tmp/venv/bin/python -m pip --version
      mkdir /tmp/proj && cd /tmp/proj
      printf "def test_sum():\n    assert sum([1, 2, 3]) == 6\n" > test_sum.py
      pytest -q
    '
    ;;
  runner-cpp)
    run '
      printf "#include <iostream>\nint main(){std::cout << 42;}\n" > /tmp/main.cpp
      g++ -std=c++20 -Wall -Wextra -Werror /tmp/main.cpp -o /tmp/smoke-gcc
      test "$(/tmp/smoke-gcc)" = 42
      clang++ -std=c++20 -fuse-ld=lld /tmp/main.cpp -o /tmp/smoke-clang
      test "$(/tmp/smoke-clang)" = 42
      mkdir /tmp/cmake && cd /tmp/cmake
      printf "cmake_minimum_required(VERSION 3.20)\nproject(smoke CXX)\nadd_executable(smoke /tmp/main.cpp)\n" > CMakeLists.txt
      cmake -S . -B build -G Ninja >/dev/null
      cmake --build build >/dev/null
      test "$(./build/smoke)" = 42
      ccache --version >/dev/null
      meson --version
    '
    ;;
  runner-dotnet8)
    run '
      dotnet --version | grep -Eq "^8\."
      mkdir /tmp/smoke && cd /tmp/smoke
      dotnet new console --no-restore >/dev/null
      test "$(dotnet run)" = "Hello, World!"
    '
    ;;
  runner-node22)
    run '
      node --version | grep -Eq "^v22\."
      npm --version
      pnpm --version
      yarn --version
      test "$(node -p "6 * 7")" = 42
    '
    ;;
  *)
    echo "No smoke test for $name" >&2
    exit 2
    ;;
esac
echo "Smoke test passed: $image"
