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

- **Enhanced Firewall**:
  - Adds bidirectional traffic filtering, allowing secure Thread and LAN communication while restricting unauthorized access.

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
  - `FIREWALL`: Enable or disable OTBR Firewall rules (e.g., `1` enabled (default), `0` disabled).
  - `NAT64`: Enable or disable NAT64 rules (e.g., `1` enabled (default), `0` disabled).

## What's Next
- **Coming Soon**:
  - ✅ ~User-defined REST API port.~
  - ✅ ~Web UI enabled with user-defined port.~
  - ✅ ~Environment variables to enable/disable the Firewall and NAT64.~
  - ???

## System Configuration
### ⚠️ IMPORTANT NOTE 
 - The ip6table_filter module is required for the OTBR firewall to function.
 - The sysctl settings are required for the Thread network to operate correctly, enabling IPv6, forwarding, and proper router advertisement handling.

Load the ip6table_filter module and ensure it persists across reboots:
```
sudo modprobe ip6table_filter
echo "ip6table_filter" | sudo tee -a /etc/modules-load.d/ip6table_filter.conf
```

Add the following to enable IPv6, forwarding, and router advertisements on the host for the Thread network:
```
echo "net.ipv6.conf.all.disable_ipv6 = 0" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_ra_rt_info_max_plen = 64" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_ra = 2" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

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
      - ./otbr:/data/thread # Thread network persistent data storage
      - /etc/localtime:/etc/localtime:ro
    environment:
      NETWORK_DEVICE:  #Network Device (Leave empty, remove, or comment out if not used)
      DEVICE: /dev/ttyUSB0 #RCP Device Path
      BAUDRATE: 460800 #RCP Baudrate
      FLOW_CONTROL: 1 #Hardware Flow Control
      BACKBONE_NET: eth0 #Main Network Interface
      THREAD_NET: wpan0 #Thread Network Interface
      WEB_PORT: 8080 # User-defined Web UI port
      REST_PORT: 8081 # User Defined REST API PORT
      LOG_LEVEL: 3 # emergency=0 alert=1 critical=2 error=3 warning=4 notice=5 info=6 debug=7
      FIREWALL: 1 # Enable OTBR Enhanced Firewall
      NAT64: 1 # Enable NAT64 rules
    devices:
      - /dev/ttyUSB0
      - /dev/net/tun
```

## Auto release triggered by `openthread/border-router`

  - This repository auto releases a multiarch image which is triggered by `openthread/border-router` image releases so it's always up to date. Works best with recent RCP firmware.
