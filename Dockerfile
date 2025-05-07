# Copyright (c) 2025, The OpenThread Authors.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the
#    names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Build stage
FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS builder

ARG GITHUB_REPO="openthread/ot-br-posix"
ARG GIT_COMMIT="HEAD"
ARG TARGETARCH

ENV MDNS_RESPONDER_SOURCE_NAME=mDNSResponder-1790.80.10
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV WEB_GUI=1
ENV REST_API=1
ENV OTBR_MDNS=mDNSResponder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /usr/src

# Install build dependencies, including dependencies needed by ot-br-posix's script/bootstrap
# Note: Some of these dependencies may be redundant since script/bootstrap installs them.
# We keep them to ensure the build succeeds, but they could be trimmed in the future.
# Removed libavahi-compat-libdnssd-dev to avoid conflicts with mDNSResponder's dns_sd.h
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libavahi-client-dev \
        libavahi-common-dev \
        libavahi-core-dev \
        libavahi-glib-dev \
        libmicrohttpd-dev \
        libprotobuf-dev \
        libnetfilter-queue-dev \
        libdbus-1-dev \
        libreadline-dev \
        libncurses-dev \
        libjsoncpp-dev \
        libboost-dev \
        libssl-dev \
        libevent-dev \
        libglib2.0-dev \
        python3 \
        ninja-build \
        pkg-config \
        protobuf-compiler \
        wget \
        lsb-release \
        sudo \
        psmisc \
        avahi-utils && \
    rm -rf /var/lib/apt/lists/*

# Clone ot-br-posix
RUN git clone --depth 1 -b main "https://github.com/${GITHUB_REPO}.git"

# Copy the custom otbr-agent/run script to overwrite the default
COPY s6-overlay/s6-rc.d/otbr-agent/run /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/run

# Copy the new otbr-web directory
COPY s6-overlay/s6-rc.d/otbr-web/ /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/otbr-web/

# Copy the user/contents.d/otbr-web file to add otbr-web to user services
COPY s6-overlay/s6-rc.d/user/contents.d/otbr-web /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/otbr-web

# Run ot-br-posix's bootstrap script to install dependencies (including Node.js and mDNSResponder)
RUN cd ot-br-posix && \
    git fetch origin "${GIT_COMMIT}" && \
    git checkout "${GIT_COMMIT}" && \
    git submodule update --depth 1 --init && \
    ./script/bootstrap || { echo "script/bootstrap failed"; exit 1; }

# Build ot-br-posix with mDNSResponder include and library paths, enable REST API and Web UI
RUN mkdir -p ot-br-posix/build/otbr && \
    cd ot-br-posix && \
    cmake -S /usr/src/ot-br-posix -B /usr/src/ot-br-posix/build/otbr -GNinja \
        -DCMAKE_INSTALL_PREFIX=/install/usr \
        -DBUILD_TESTING=OFF \
        -DOTBR_BORDER_ROUTING=ON \
        -DOTBR_BACKBONE_ROUTER=ON \
        -DOTBR_DBUS=OFF \
        -DOTBR_MDNS=mDNSResponder \
        -DOTBR_DNSSD_DISCOVERY_PROXY=ON \
        -DOTBR_SRP_ADVERTISING_PROXY=ON \
        -DOTBR_TREL=ON \
        -DOTBR_NAT64=ON \
        -DOTBR_DNS_UPSTREAM_QUERY=ON \
        -DOT_POSIX_NAT64_CIDR="192.168.255.0/24" \
        -DOT_FIREWALL=ON \
        -DOTBR_REST=ON \
        -DOTBR_WEB=ON \
        -DOTBR_CLI=ON \
        -DCMAKE_C_FLAGS="-I/usr/include" \
        -DCMAKE_CXX_FLAGS="-I/usr/include" \
        -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib -ldns_sd -Wl,-rpath=/usr/lib" \
        || { echo "CMake failed"; exit 1; }

# Run ninja to build
RUN cd ot-br-posix/build/otbr && \
    ninja || { echo "ninja failed"; exit 1; }

# Run ninja install to install artifacts
RUN cd ot-br-posix/build/otbr && \
    ninja install || { echo "ninja install failed"; exit 1; }

# Runtime stage
FROM ubuntu:24.04

ARG TARGETARCH

ENV S6_OVERLAY_VERSION=3.1.6.2
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV INFRA_IF_NAME=eth0
ENV BORDER_ROUTING=1
ENV BACKBONE_ROUTER=1
ENV OT_BACKBONE_CI=0
ENV OTBR_MDNS=mDNSResponder
ENV OTBR_OPTIONS=
ENV PLATFORM=Ubuntu
ENV REFERENCE_DEVICE=0
ENV RELEASE=1
ENV NAT64=1
ENV NAT64_DYNAMIC_POOL=192.168.255.0/24
ENV DNS64=0
ENV WEB_GUI=1
ENV REST_API=1
ENV FIREWALL=1
ENV OT_SRP_ADV_PROXY=0
ENV DOCKER=1
ENV DEVICE=/dev/ttyUSB0
ENV NETWORK_DEVICE=""
ENV BAUDRATE=460800
ENV FLOW_CONTROL=1
ENV BACKBONE_NET=eth0
ENV THREAD_NET=wpan0
ENV LOG_LEVEL=4
ENV WEB_PORT=8080
ENV REST_PORT=8081

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy artifacts from builder stage and set up runtime environment
RUN --mount=type=bind,source=/,target=/builder,from=builder \
    mkdir -p /usr/sbin /usr/lib/x86_64-linux-gnu /install/usr/share/otbr-web && \
    cp -r /builder/install/usr/sbin/* /usr/sbin/ && \
    cp /builder/usr/sbin/mdnsd /usr/sbin/mdnsd && \
    cp /builder/usr/lib/libdns_sd.so.1 /usr/lib/x86_64-linux-gnu/libdns_sd.so.1 && \
    ln -sf libdns_sd.so.1 /usr/lib/x86_64-linux-gnu/libdns_sd.so && \
    ldconfig && \
    cp -r /builder/install/usr/share/otbr-web/* /install/usr/share/otbr-web/ && \
    cp -r /builder/usr/src/ot-br-posix/etc/docker/border-router/rootfs/* / && \
    echo "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    mkdir -p /run/systemd/system && \
    apt-get update && \
    apt-get install -y \
        libavahi-client3 \
        libavahi-common3 \
        libmnl0 \
        libnfnetlink0 \
        libnss-mdns \
        libmicrohttpd12 \
        libprotobuf32 \
        libjsoncpp25 \
        libreadline8 \
        curl \
        xz-utils \
        ipset \
        iptables && \
    echo -e "# Enable mDNS for the following domains\nlocal\n0.in-addr.arpa\n8.e.f.ip6.arpa\n9.e.f.ip6.arpa\na.e.f.ip6.arpa\nb.e.f.ip6.arpa" > /etc/nss_mdns.conf && \
    case "${TARGETARCH}" in \
        amd64) S6_ARCH="x86_64" ;; \
        arm64) S6_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -L -f -o /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" && \
    curl -L -f -o /tmp/s6-overlay-${S6_ARCH}.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    tar -Jxvf /tmp/s6-overlay-noarch.tar.xz -C / && \
    tar -Jxvf /tmp/s6-overlay-${S6_ARCH}.tar.xz -C / && \
    rm -rf /var/lib/apt/lists/* /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-${S6_ARCH}.tar.xz /usr/sbin/policy-rc.d && \
    chmod +x /etc/s6-overlay/s6-rc.d/otbr-agent/run /etc/s6-overlay/s6-rc.d/otbr-agent/finish /etc/s6-overlay/s6-rc.d/otbr-agent/data/* && \
    chmod +x /etc/s6-overlay/s6-rc.d/otbr-web/run /etc/s6-overlay/s6-rc.d/otbr-web/finish

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f http://localhost:8081/node/state | grep -Eq '"router"|"leader"' && curl -f http://localhost:${WEB_PORT:-8080}/ || exit 1

ENTRYPOINT ["/init"]
