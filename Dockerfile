#
#  Copyright (c) 2025, The OpenThread Authors.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  3. Neither the name of the copyright holder nor the
#     names of its contributors may be used to endorse or promote products
#     derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#

# Build stage
FROM ubuntu:24.04 AS builder

ARG GITHUB_REPO="openthread/ot-br-posix"
ARG GIT_COMMIT="HEAD"

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /usr/src

# Install build dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           build-essential \
           ca-certificates \
           cmake \
           git \
           libjsoncpp-dev \
           ninja-build \
           nodejs \
           npm \
           pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Clone ot-br-posix and checkout target commit
RUN git clone --depth 1 -b main "https://github.com/${GITHUB_REPO}.git" \
    && cd ot-br-posix \
    && git fetch origin "${GIT_COMMIT}" \
    && git checkout "${GIT_COMMIT}" \
    && git submodule update --depth 1 --init --recursive

# Copy custom s6 service scripts to override upstream defaults
COPY s6-overlay/s6-rc.d/otbr-agent/run /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/run
COPY s6-overlay/s6-rc.d/otbr-agent/finish /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/finish
COPY s6-overlay/s6-rc.d/otbr-web/run /usr/src/ot-br-posix/etc/docker/border-router/rootfs/etc/s6-overlay/s6-rc.d/otbr-web/run

# Create custom OpenThread config for Home Assistant optimization
RUN cat <<'EOF' > /usr/src/openthread-core-custom-config-posix.h
#ifndef OPENTHREAD_CORE_CUSTOM_CONFIG_POSIX_H_
#define OPENTHREAD_CORE_CUSTOM_CONFIG_POSIX_H_

#define OPENTHREAD_POSIX_CONFIG_NETIF_PREFIX_ROUTE_METRIC 64
#define OPENTHREAD_CONFIG_DELAY_AWARE_QUEUE_MANAGEMENT_FRAG_TAG_ENTRY_LIST_SIZE 64

#endif /* OPENTHREAD_CORE_CUSTOM_CONFIG_POSIX_H_ */
EOF

# Build ot-br-posix with OpenThread mDNS, REST API, Web UI, and NAT64
RUN cd ot-br-posix \
    && mkdir build && cd build \
    && cmake -GNinja \
           -DCMAKE_INSTALL_PREFIX=/usr \
           -DBUILD_TESTING=OFF \
           -DOTBR_BORDER_ROUTING=ON \
           -DOTBR_BACKBONE_ROUTER=ON \
           -DOTBR_DBUS=OFF \
           -DOTBR_MDNS=openthread \
           -DOTBR_DNSSD_DISCOVERY_PROXY=ON \
           -DOTBR_SRP_ADVERTISING_PROXY=ON \
           -DOTBR_TREL=ON \
           -DOT_POSIX_NAT64_CIDR="192.168.255.0/24" \
           -DOT_FIREWALL=ON \
           -DOTBR_REST=ON \
           -DOTBR_WEB=ON \
           -DOTBR_CLI=ON \
           -DOT_RCP_RESTORATION_MAX_COUNT=2 \
           -DOT_PROJECT_CONFIG="/usr/src/openthread-core-custom-config-posix.h" \
           .. \
    && ninja \
    && ninja install

# Runtime stage
FROM ubuntu:24.04

ARG TARGETARCH
ARG TARGETVARIANT

ENV S6_OVERLAY_VERSION=3.2.1.0
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install runtime dependencies and s6-overlay
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           curl \
           ipset \
           iproute2 \
           iptables \
           libjsoncpp25 \
           xz-utils \
    && PLATFORM_SPEC="${TARGETARCH}${TARGETVARIANT:+/$TARGETVARIANT}" \
    && case "${PLATFORM_SPEC}" in \
         "amd64") S6_ARCH="x86_64" ;; \
         "arm64") S6_ARCH="aarch64" ;; \
         *) echo "Unsupported architecture: ${PLATFORM_SPEC}"; exit 1 ;; \
       esac \
    && curl -L -f -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        | tar Jxvf - -C / \
    && curl -L -f -s "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        | tar Jxvf - -C / \
    && rm -rf /var/lib/apt/lists/*

# Copy built binaries from builder
COPY --from=builder /usr/sbin/otbr-agent /usr/sbin/
COPY --from=builder /usr/sbin/otbr-web /usr/sbin/
COPY --from=builder /usr/sbin/ot-ctl /usr/sbin/
COPY --from=builder /usr/share/otbr-web/ /usr/share/otbr-web/

# Copy s6 rootfs (includes our custom overrides applied in builder stage)
COPY --from=builder /usr/src/ot-br-posix/etc/docker/border-router/rootfs/ /

# Set permissions for s6 service scripts
RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/otbr-agent/run \
    /etc/s6-overlay/s6-rc.d/otbr-agent/finish \
    /etc/s6-overlay/s6-rc.d/otbr-agent/data/check \
    /etc/s6-overlay/s6-rc.d/otbr-web/run \
    /etc/s6-overlay/s6-rc.d/otbr-web/finish

# Default environment variables
ENV DEVICE=/dev/ttyUSB0 \
    NETWORK_DEVICE="" \
    BAUDRATE=460800 \
    FLOW_CONTROL=1 \
    BACKBONE_NET=eth0 \
    THREAD_NET=wpan0 \
    LOG_LEVEL=4 \
    WEB_PORT=8080 \
    REST_PORT=8081 \
    FIREWALL=1 \
    NAT64=1

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:${REST_PORT:-8081}/node || exit 1

ENTRYPOINT ["/init"]
