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

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /usr/src

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libavahi-client-dev \
        libavahi-common-dev \
        ninja-build \
        wget && \
    rm -rf /var/lib/apt/lists/*

# Clone ot-br-posix first to access patch files
RUN git clone --depth 1 -b main "https://github.com/${GITHUB_REPO}.git"

# Clone and build mDNSResponder
RUN shopt -s nullglob && \
    wget --no-check-certificate "https://github.com/apple-oss-distributions/mDNSResponder/archive/refs/tags/$MDNS_RESPONDER_SOURCE_NAME.tar.gz" && \
    mkdir -p "$MDNS_RESPONDER_SOURCE_NAME" && \
    tar xvf "$MDNS_RESPONDER_SOURCE_NAME.tar.gz" -C "$MDNS_RESPONDER_SOURCE_NAME" --strip-components=1 && \
    cd "$MDNS_RESPONDER_SOURCE_NAME" && \
    for patch in "/usr/src/ot-br-posix/third_party/mDNSResponder/"*.patch; do patch -p1 < "$patch"; done && \
    cd mDNSPosix && \
    make os=linux tls=no && \
    mkdir -p /install/usr/sbin /install/usr/lib /install/usr/include && \
    cp build/prod/mdnsd /install/usr/sbin/mdnsd && \
    cp build/prod/libdns_sd.so /install/usr/lib/libdns_sd.so.1 && \
    ln -sf libdns_sd.so.1 /install/usr/lib/libdns_sd.so && \
    cp ../mDNSShared/dns_sd.h /install/usr/include/dns_sd.h

# Build ot-br-posix with mDNSResponder include and library paths, enable ot-ctl and REST API
RUN cd ot-br-posix && \
    git fetch origin "${GIT_COMMIT}" && \
    git checkout "${GIT_COMMIT}" && \
    git submodule update --depth 1 --init && \
    cmake -GNinja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr \
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
        -DOPENTHREAD_POSIX=ON \
        -DOTBR_POSIX_CONFIG_CLI=ON \
        -DOTBR_REST=ON \
        -DCMAKE_C_FLAGS="-I/install/usr/include" \
        -DCMAKE_CXX_FLAGS="-I/install/usr/include" \
        -DCMAKE_EXE_LINKER_FLAGS="-L/install/usr/lib" \
        -DCMAKE_INSTALL_PREFIX=/install/usr && \
    ninja && \
    ninja install && \
    cp third_party/openthread/repo/src/posix/ot-ctl /install/usr/sbin/ot-ctl || echo "ot-ctl not found in build, skipping"

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
ENV OTBR_DOCKER_REQS="sudo python3"
ENV OTBR_DOCKER_DEPS="git ca-certificates"
ENV OTBR_BUILD_DEPS="apt-utils build-essential psmisc ninja-build cmake wget ca-certificates libreadline-dev libncurses-dev libdbus-1-dev libavahi-common-dev libavahi-client-dev libnetfilter-queue-dev"
ENV OTBR_OT_BACKBONE_CI_DEPS="curl lcov wget build-essential python3-dbus python3-zeroconf socat"

# Default values for custom variables
ENV DEVICE=/dev/ttyUSB0
ENV NETWORK_DEVICE=""
ENV BAUDRATE=460800
ENV FLOW_CONTROL=1
ENV BACKBONE_NET=eth0
ENV THREAD_NET=wpan0
ENV LOG_LEVEL=3

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install runtime dependencies and configure avahi-daemon
RUN apt-get update && \
    apt-get install -y \
        avahi-daemon \
        avahi-utils \
        ipset \
        iptables \
        kmod \
        libavahi-client3 \
        libavahi-common3 \
        libkmod2 \
        libmnl0 \
        libnfnetlink0 \
        libnss-mdns \
        curl \
        xz-utils && \
    mkdir -p /run/systemd/system && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure avahi-daemon || true && \
    /var/lib/dpkg/info/avahi-daemon.postinst configure || true && \
    echo -e "# Enable mDNS for the following domains\nlocal\n0.in-addr.arpa\n8.e.f.ip6.arpa\n9.e.f.ip6.arpa\na.e.f.ip6.arpa\nb.e.f.ip6.arpa" > /etc/nss_mdns.conf && \
    rm -rf /var/lib/apt/lists/*

# Install s6-overlay
RUN case "${TARGETARCH}" in \
        amd64) S6_ARCH="x86_64" ;; \
        arm64) S6_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -L -f -o /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" && \
    curl -L -f -o /tmp/s6-overlay-${S6_ARCH}.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    tar -Jxvf /tmp/s6-overlay-noarch.tar.xz -C / && \
    tar -Jxvf /tmp/s6-overlay-${S6_ARCH}.tar.xz -C / && \
    rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-${S6_ARCH}.tar.xz

# Copy built artifacts from builder stage
COPY --from=builder /install  /install /

# Copy rootfs from builder stage
COPY --from=builder /usr/src/ot-br-posix/etc/docker/border-router/rootfs /

# Modify otbr-agent run script to use custom variables and dynamically construct RCP_DEVICE
RUN sed -n '/^#!/,/^echo "Starting otbr-agent..."/p' /etc/s6-overlay/s6-rc.d/otbr-agent/run > /tmp/run_tmp && \
    echo '# Debug: Log script start' >> /tmp/run_tmp && \
    echo 'echo "otbr-agent run script started"' >> /tmp/run_tmp && \
    echo '# Map user-friendly variables to local variables to avoid readonly issues' >> /tmp/run_tmp && \
    echo 'RCP_DEVICE=${DEVICE:-${OT_RCP_DEVICE:-/dev/ttyUSB0}}' >> /tmp/run_tmp && \
    echo 'BAUDRATE_LOCAL=${BAUDRATE:-460800}' >> /tmp/run_tmp && \
    echo 'FLOW_CONTROL_LOCAL=${FLOW_CONTROL:-1}' >> /tmp/run_tmp && \
    echo 'INFRA_IF=${BACKBONE_NET:-${OT_INFRA_IF:-eth0}}' >> /tmp/run_tmp && \
    echo 'THREAD_IF=${THREAD_NET:-${OT_THREAD_IF:-wpan0}}' >> /tmp/run_tmp && \
    echo 'LOG_LEVEL_LOCAL=${LOG_LEVEL:-${OT_LOG_LEVEL:-3}}' >> /tmp/run_tmp && \
    echo '# Debug: Log variable values' >> /tmp/run_tmp && \
    echo 'echo "DEVICE=$DEVICE, NETWORK_DEVICE=$NETWORK_DEVICE, BAUDRATE=$BAUDRATE_LOCAL, FLOW_CONTROL=$FLOW_CONTROL_LOCAL"' >> /tmp/run_tmp && \
    echo 'echo "INFRA_IF=$INFRA_IF, THREAD_IF=$THREAD_IF, LOG_LEVEL_LOCAL=$LOG_LEVEL_LOCAL"' >> /tmp/run_tmp && \
    echo '# Dynamically construct RCP_DEVICE with explicit FLOW_CONTROL logic' >> /tmp/run_tmp && \
    echo '[ "${FLOW_CONTROL_LOCAL}" = "1" ] && FLOW_CONTROL_PARAM="&uart-flow-control" || FLOW_CONTROL_PARAM="&uart-init-deassert"' >> /tmp/run_tmp && \
    echo 'if [ -n "$NETWORK_DEVICE" ]; then RCP_DEVICE="spinel+hdlc+uart://$NETWORK_DEVICE?uart-baudrate=$BAUDRATE_LOCAL$FLOW_CONTROL_PARAM"; else RCP_DEVICE="spinel+hdlc+uart://$RCP_DEVICE?uart-baudrate=$BAUDRATE_LOCAL$FLOW_CONTROL_PARAM"; fi' >> /tmp/run_tmp && \
    echo '# Debug: Log the constructed RCP_DEVICE' >> /tmp/run_tmp && \
    echo 'echo "Constructed RCP_DEVICE: $RCP_DEVICE"' >> /tmp/run_tmp && \
    echo 'exec s6-notifyoncheck -d -s 300 -w 300 -n 0 stdbuf -oL \' >> /tmp/run_tmp && \
    echo '     "/usr/sbin/otbr-agent" \' >> /tmp/run_tmp && \
    echo '     --rest-listen-port "${OTBR_REST_PORT:=8081}" \' >> /tmp/run_tmp && \
    echo '     -d"${LOG_LEVEL_LOCAL}" -v -s \' >> /tmp/run_tmp && \
    echo '     -I "${THREAD_IF}" \' >> /tmp/run_tmp && \
    echo '     -B "${INFRA_IF}" \' >> /tmp/run_tmp && \
    echo '     "${RCP_DEVICE}" \' >> /tmp/run_tmp && \
    echo '     "trel://${INFRA_IF}"' >> /tmp/run_tmp && \
    cp /tmp/run_tmp /etc/s6-overlay/s6-rc.d/otbr-agent/run && \
    chmod +x /etc/s6-overlay/s6-rc.d/otbr-agent/run && \
    rm /tmp/run_tmp

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD ot-ctl state

ENTRYPOINT ["/init"]
