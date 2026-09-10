# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      gdb \
      ninja-build \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

USER runner
RUN gcc -dumpversion | grep -Eq '^12($|\.)' \
    && cmake --version \
    && ninja --version

LABEL org.opencontainers.image.title="runner-cpp" \
      org.opencontainers.image.description="Gitea Actions job image with GCC 12, CMake and Ninja"
