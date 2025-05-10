[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/d34dc3n73r/otbr-docker/build.yml?logo=docker&logoSize=auto&label=DOCKER%20BUILD&cacheSeconds=3600)](https://github.com/d34dc3n73r/otbr-docker/pkgs/container/otbr-docker) [![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/d34dc3n73r/otbr-docker/release.yml?logo=github&logoSize=auto&label=AUTO-RELEASE&cacheSeconds=3600)](https://github.com/D34DC3N73R/otbr-docker/releases/)
[![GHCR Version][ghcr-version-svg]][ghcr]

---

# OpenThread Border Router (OTBR) Docker

This repository provides a lightweight OpenThread Border Router (OTBR) setup, with the REST API enabled. Built from source using `openthread/ot-br-posix`, this image is designed for ease of use in Home Assistant.

## Key Features

### **🪶 <ins>Lightweight Image</ins>**:  
Image size is approximately 118 MB, making it efficient for deployment on resource-constrained devices. 
  
### **🤖 <ins>REST API Enabled</ins>**:  
Includes the REST API with a user-defined port.

### **🌐 <ins>Web UI Enabled</ins>**:  
Enabled with a user-defined port.

### **🛠️ <ins>Multiarch</ins>**:  
Built for `amd64` and `arm64` architectures.

### **🔒 <ins>Enhanced Firewall</ins>**:  
Adds bidirectional traffic filtering, allowing secure Thread and LAN communication while restricting unauthorized access.  

### <ins>**Convenient Environment Variables**</ins>:  
$\hspace{15pt}$`NETWORK_DEVICE`: _Not tested._  
$\hspace{15pt}$`DEVICE`: _Serial device (e.g., `/dev/ttyUSB0`)._  
$\hspace{15pt}$`BAUDRATE`: _Serial baud rate (e.g., `460800`)._  
$\hspace{15pt}$`FLOW_CONTROL`: _Hardware flow control (e.g., `1` for enabled, `0` for disabled)._  
$\hspace{15pt}$`BACKBONE_NET`: _Infrastructure interface (e.g., `eth0`)._   
$\hspace{15pt}$`THREAD_NET`: _Thread interface (e.g., `wpan0`)._  
$\hspace{15pt}$`WEB_PORT`: _User-defined Web UI port (default `8080`)._  
$\hspace{15pt}$`REST_PORT`: _User-defined REST API port (default `8081`)._  
$\hspace{15pt}$`LOG_LEVEL`: _OTBR log level (EMERG:`0` ALERT:`1` CRIT:`2` ERR:`3` WARN:`4` NOTICE:`5` INFO:`6` DEBUG:`7`)._  
$\hspace{15pt}$`FIREWALL`: _Enable or disable OTBR Firewall rules (e.g., `1` enabled (default), `0` disabled)._  
$\hspace{15pt}$~`NAT64`: _Enable or disable NAT64 rules (e.g., `1` enabled (default), `0` disabled)._~  

_* NAT64 disabled due to the removal of the DNS64 feature in ot-br-posix (commit f8aa002f905fc5890d3a6aa0802e2fda6bf18f4b) and a build system dependency that forces OTBR_NAT64_BORDER_ROUTING=ON when OTBR_NAT64=ON, preventing independent control of NAT64 border routing._

## What's Next
**Coming Soon**:  
- [x] ~User-defined REST API port.~  
- [x] ~Web UI enabled with user-defined port.~  
- [x] ~Environment variables to enable/disable the Firewall and NAT64.~  
- [ ] ???  

## System Configuration

---

### ⚠️ <ins>**IMPORTANT NOTE**</ins> ⚠️   
🟠 **The ip6table_filter module is required for the OTBR firewall to function.**  
🟠 **Sysctl settings required for Thread to operate correctly, enabling IPv6, forwarding, and proper RA handling.**

---

Load the ip6table_filter module and ensure it persists across reboots:
```bash
sudo modprobe ip6table_filter
echo "ip6table_filter" | sudo tee -a /etc/modules-load.d/ip6table_filter.conf
```

Add the following to enable IPv6, forwarding, and router advertisements on the host for the Thread network:
```bash
echo "net.ipv6.conf.all.disable_ipv6 = 0" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_ra_rt_info_max_plen = 64" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_ra = 2" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## Docker Compose
```yaml
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
      NETWORK_DEVICE: # Network Device (Leave empty, remove, or comment out if not used)
      DEVICE: /dev/ttyUSB0 # RCP Device Path
      BAUDRATE: 460800 # RCP Baudrate
      FLOW_CONTROL: 1 # Hardware Flow Control
      BACKBONE_NET: eth0 # Main Network Interface
      THREAD_NET: wpan0 # Thread Network Interface
      WEB_PORT: 8080 # User-defined Web UI port
      REST_PORT: 8081 # User Defined REST API PORT
      LOG_LEVEL: 3 # emergency=0 alert=1 critical=2 error=3 warning=4 notice=5 info=6 debug=7
      FIREWALL: 1 # Enable OTBR Enhanced Firewall
      # NAT64 disabled due to the removal of the DNS64 feature in ot-br-posix
      # (commit f8aa002f905fc5890d3a6aa0802e2fda6bf18f4b) and a build system dependency
      # that forces OTBR_NAT64_BORDER_ROUTING=ON when OTBR_NAT64=ON, preventing
      # independent control of NAT64 border routing.
      #NAT64: 0 # Enable NAT64 rules
    devices:
      - /dev/ttyUSB0
      - /dev/net/tun
```

## Auto release triggered by `openthread/border-router`

  - This repository auto releases a multiarch image which is triggered by `openthread/border-router` image releases so it's always up to date. Works best with recent RCP firmware.


[ghcr-version-svg]: https://img.shields.io/github/v/release/D34DC3N73R/otbr-docker?label=LATEST
[ghcr]: https://github.com/D34DC3N73R/otbr-docker/pkgs/container/otbr-docker
