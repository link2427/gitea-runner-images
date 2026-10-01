# syntax=docker/dockerfile:1
FROM docker:29-cli AS docker-cli

FROM node:22-bookworm-slim

ARG REVISION=development
ARG VERSION=development

# Everything a job might reach for is installed up front: the target hosts have
# no package mirror, so a missing tool means building and burning a new bundle.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      bzip2 \
      ca-certificates \
      curl \
      file \
      gettext-base \
      git \
      git-lfs \
      gnupg \
      jq \
      less \
      lsb-release \
      make \
      netcat-openbsd \
      openssh-client \
      openssl \
      patch \
      procps \
      python3 \
      rsync \
      sudo \
      tar \
      time \
      tree \
      unzip \
      wget \
      xz-utils \
      zip \
      zstd \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash runner \
    && printf 'runner ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Register the bundled Node.js in the hosted tool cache so that
# actions/setup-node with node-version 22 resolves locally instead of
# downloading.
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
RUN node_version="$(node -p 'process.versions.node')" \
    && mkdir -p "$RUNNER_TOOL_CACHE/node/$node_version" \
    && ln -s /usr/local "$RUNNER_TOOL_CACHE/node/$node_version/x64" \
    && touch "$RUNNER_TOOL_CACHE/node/$node_version/x64.complete" \
    && chown -R runner:runner "$RUNNER_TOOL_CACHE"

# Node.js and Python's requests ship their own CA lists; point them at the
# system store, which the installer extends with the site's own CAs.
ENV CI=true \
    HOME=/home/runner \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NPM_CONFIG_PREFIX=/home/runner/.npm-global \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    PATH=/home/runner/.npm-global/bin:/home/runner/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.title="runner-base" \
      org.opencontainers.image.description="General-purpose Gitea Actions job image for offline hosts" \
      org.opencontainers.image.source="https://github.com/link2427/gitea-runner-images" \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.version=$VERSION

WORKDIR /workspace
USER runner
CMD ["bash"]
