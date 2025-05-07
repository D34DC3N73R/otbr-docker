# OpenThread Border Router (OTBR) Docker

This repository provides a lightweight OpenThread Border Router (OTBR) setup, with the REST API enabled. Built from source using `openthread/ot-br-posix`, this image is designed for ease of use in Home Assistant.

## Key Features

- **Lightweight Image**:
  - Image size is approximately 118 MB, making it efficient for deployment on resource-constrained devices. 
  
- **REST API Enabled**:
  - Includes the REST API with a user-defined port.

- **Web UI Enabled**:
  - Enabled with a user-defined port.

- **Multiarch**:
  - Built for `amd64` and `arm64` architectures.

- **Convenient Environment Variables**:
  - `NETWORK_DEVICE`: Not tested.
  - `DEVICE`: Serial device (e.g., `/dev/ttyUSB0`).
  - `BAUDRATE`: Serial baud rate (e.g., `460800`).
  - `FLOW_CONTROL`: Hardware flow control (e.g., `1` for enabled, `0` for disabled).
  - `BACKBONE_NET`: Infrastructure interface (e.g., `eth0`).
  - `THREAD_NET`: Thread interface (e.g., `wpan0`).
  - `WEB_PORT`: User-defined Web UI port (default `8080`).
  - `REST_PORT`: User-defined REST API port (default `8081`).
  - `LOG_LEVEL`: OTBR log level (emergency=`0` alert=`1` critical=`2` error=`3` warning=`4` notice=`5` info=`6` debug=`7`). 

- **Firewall and NAT64 Enabled**:
  - Firewall and NAT64 are enabled by default for enhanced security and IPv4/IPv6 interoperability.

## Differences from `openthread/border-router`

- **REST API Support**:
  - This image includes the REST API on a user-defined port.
- **Web UI Enabled**:
  - Web UI binary included.
- **Healthcheck**:
  - Integrated container health check.
- **"Date" release tags**:
  - Easily roll back with `:vYYYY.MM.DD` image tags.
- **Enhanced Configuration**:
  - Provides user-friendly environment variables and flow control options.

## What's Next
- **Coming Soon**:
  - ✅ ~User-defined REST API port.~
  - ✅ ~Web UI enabled with user-defined port.~
  - Environment variables to enable/disable the Firewall and NAT64. Both are currently enabled.

## Docker Compose
```
services:
  otbr:
    image: ghcr.io/d34dc3n73r/otbr-docker
    container_name: otbr
    network_mode: host
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
      - NET_RAW
    volumes:
      - /path/to/docker-confs/otbr:/data/thread # Thread network persistent data storage
      - /etc/localtime:/etc/localtime:ro
    environment:
      - NETWORK_DEVICE= #Network Device (Leave empty, remove, or comment out if not used)
      - DEVICE=/dev/ttyUSB0 #RCP Device Path
      - BAUDRATE=460800 #RCP Baudrate
      - FLOW_CONTROL=1 #Hardware Flow Control
      - BACKBONE_NET=eth0 #Main Network Interface
      - THREAD_NET=wpan0 #Thread Network Interface
      - WEB_PORT=8080 # User Defined Web UI port
      - REST_PORT=8081 # User Defined REST API PORT
      - LOG_LEVEL=3
    devices:
      - /dev/ttyUSB0
      - /dev/net/tun
```

## Auto release triggered by `openthread/border-router`

  - This repository auto releases a multiarch image which is triggered by `openthread/border-router` image releases so it's always up to date. Works best with recent RCP firmware.
