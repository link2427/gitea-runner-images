# syntax=docker/dockerfile:1
FROM node:25-bookworm-slim

ARG REVISION=development
ARG VERSION=development

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      file \
      git \
      git-lfs \
      gnupg \
      jq \
      openssh-client \
      procps \
      sudo \
      tar \
      unzip \
      xz-utils \
      zip \
      zstd \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash runner \
    && printf 'runner ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

ENV CI=true \
    HOME=/home/runner

LABEL org.opencontainers.image.title="runner-base" \
      org.opencontainers.image.description="General-purpose Gitea Actions job image" \
      org.opencontainers.image.source="https://github.com/link2427/gitea-runner-images" \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.version=$VERSION

WORKDIR /workspace
USER runner
CMD ["bash"]
