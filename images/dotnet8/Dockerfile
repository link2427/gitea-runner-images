# syntax=docker/dockerfile:1
ARG BASE_IMAGE=runner-base:local
FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim AS dotnet

FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libc6 \
      libgcc-s1 \
      libgssapi-krb5-2 \
      libicu72 \
      libssl3 \
      libstdc++6 \
      zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dotnet /usr/share/dotnet /usr/share/dotnet
RUN ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet

ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    NUGET_XMLDOC_MODE=skip

USER runner
RUN dotnet --version | grep -Eq '^8\.'

LABEL org.opencontainers.image.title="runner-dotnet8" \
      org.opencontainers.image.description="Gitea Actions job image with the .NET 8 SDK"
