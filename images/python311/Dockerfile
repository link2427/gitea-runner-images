# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      python3 \
      python3-dev \
      python3-pip \
      python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/local/bin/python

USER runner
RUN python --version 2>&1 | grep -Eq '^Python 3\.11\.' \
    && python -m venv /tmp/smoke-venv \
    && /tmp/smoke-venv/bin/python -m pip --version \
    && rm -rf /tmp/smoke-venv

LABEL org.opencontainers.image.title="runner-python311" \
      org.opencontainers.image.description="Gitea Actions job image with Python 3.11"
