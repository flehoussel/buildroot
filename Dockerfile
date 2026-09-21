################################
# ARG to change base image dynamically
# Useful when generating VS Code Dev Container
################################
ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

ARG USERNAME=buildroot
ARG UID=1000
ARG GID=1000

ENV LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    file \
    wget \
    cpio \
    rsync \
    python3 \
    python3-setuptools \
    git \
    unzip \
    bc \
    vim \
    libssl-dev \
    libncurses-dev \
    build-essential \
    bash \
    perl \
    ca-certificates \
    python-is-python3 \
    libfl-dev \
    wireless-regdb \
    device-tree-compiler \
    cmake \
    ninja-build \
    sudo && \
# Create user and group to not use root
# (base images like mcr.microsoft.com/devcontainers/base:* already ship a
# user/group on UID/GID 1000, e.g. "vscode" - remove it first if present so
# groupadd/useradd below don't fail with "GID/UID already exists")
    (getent passwd ${UID} | cut -d: -f1 | xargs -r userdel -r) 2>/dev/null; \
    (getent group ${GID} | cut -d: -f1 | xargs -r groupdel) 2>/dev/null; \
    groupadd --gid ${GID} ${USERNAME} && \
    useradd --uid ${UID} --gid ${GID} -m ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME} && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    apt-get autoremove -y

USER ${USERNAME}

WORKDIR /app

ENV SHELL=/bin/bash
