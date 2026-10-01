# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN corepack enable

# Corepack normally downloads package managers on first use. Fetch them now so
# `pnpm` and `yarn` work on hosts without internet access.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_ENABLE_AUTO_PIN=0
USER runner
RUN corepack install --global pnpm@latest yarn@stable yarn@1 \
    && node --version | grep -Eq '^v22\.' \
    && npm --version \
    && pnpm --version \
    && yarn --version

LABEL org.opencontainers.image.title="runner-node22" \
      org.opencontainers.image.description="Gitea Actions job image with Node.js 22, npm, pnpm and Yarn"
