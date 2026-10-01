# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      build-essential \
      ccache \
      clang \
      clang-format \
      clang-tidy \
      cmake \
      gdb \
      libssl-dev \
      libtool \
      lld \
      meson \
      ninja-build \
      pkg-config \
      valgrind \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

USER runner
RUN gcc -dumpversion | grep -Eq '^12($|\.)' \
    && clang --version \
    && cmake --version \
    && ninja --version

LABEL org.opencontainers.image.title="runner-cpp" \
      org.opencontainers.image.description="Gitea Actions job image with GCC, Clang, CMake and Ninja"
