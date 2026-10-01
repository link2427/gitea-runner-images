# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libffi-dev \
      libssl-dev \
      python3 \
      python3-dev \
      python3-pip \
      python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Debian marks the system interpreter as externally managed, so a plain
# `pip install` fails. Jobs instead get a runner-owned environment on PATH,
# registered in the hosted tool cache so actions/setup-python with
# python-version 3.11 resolves locally instead of downloading.
RUN python_version="$(python3 -c 'import platform; print(platform.python_version())')" \
    && python3 -m venv /opt/python \
    && /opt/python/bin/python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/python/bin/python -m pip install --no-cache-dir build pytest pytest-cov virtualenv \
    && mkdir -p "$RUNNER_TOOL_CACHE/Python/$python_version" \
    && ln -s /opt/python "$RUNNER_TOOL_CACHE/Python/$python_version/x64" \
    && touch "$RUNNER_TOOL_CACHE/Python/$python_version/x64.complete" \
    && chown -R runner:runner /opt/python "$RUNNER_TOOL_CACHE"

ENV PATH=/opt/python/bin:$PATH \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

USER runner
RUN python --version 2>&1 | grep -Eq '^Python 3\.11\.' \
    && pip --version \
    && pytest --version

LABEL org.opencontainers.image.title="runner-python311" \
      org.opencontainers.image.description="Gitea Actions job image with Python 3.11"
