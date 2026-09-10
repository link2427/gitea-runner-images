# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN corepack enable

USER runner
RUN node --version | grep -Eq '^v22\.' \
    && npm --version \
    && corepack --version

LABEL org.opencontainers.image.title="runner-node22" \
      org.opencontainers.image.description="Gitea Actions job image with Node.js 22, npm and Corepack"
