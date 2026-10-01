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
# `pip install` fails. Jobs instead get a runner-owned environment on PATH.
# runner-base already registered /opt/python in the hosted tool cache, so
# actions/setup-python with python-version 3.11 resolves to it.
RUN python3 -m venv /opt/python \
    && /opt/python/bin/python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/python/bin/python -m pip install --no-cache-dir build pytest pytest-cov virtualenv \
    && chown -R runner:runner /opt/python

ENV PATH=/opt/python/bin:$PATH \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

USER runner
RUN python --version 2>&1 | grep -Eq '^Python 3\.11\.' \
    && pip --version \
    && pytest --version

LABEL org.opencontainers.image.title="runner-python311" \
      org.opencontainers.image.description="Gitea Actions job image with Python 3.11"
