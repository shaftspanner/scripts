# Monitor Docker Containers on Multiple Servers with VPS-Monitor

This is how I've setup VPS-Monitor on my Pangolin VPS.  

## Pre-requisites

I have [Pangolin](https://github.com/fosrl/pangolin) hosted on VPS hosted [Racknerd](https://www.racknerd.com/).  When I came across [VPS-Server](https://github.com/hhftechnology/vps-monitor) I wanted to try using it to monitor and control docker containers on all of my servers.  This guide assumes you already have the Pangolin stack installed and working

## Architecture



## Step 1: Monitor containers on the VPS


## docker-compose.yml
```yaml
name: pangolin
networks:
  default:
    driver: bridge
    name: pangolin
  wg:
    driver: bridge
    enable_ipv6: false
    ipam:
      driver: default
      config:
        - subnet: 10.42.42.0/24
        #- subnet: fdcc:ad94:bacf:61a3::/64

services:
  vps-monitor:
    container_name: vps-monitor
    image: hhftechnology/vps-monitor:latest
    restart: unless-stopped
    network_mode: "container:wg-easy"
    #ports:
    #  - "6789:6789" # Port is available through the wg-easy container
    #volumes:
    #  - /var/run/docker.sock:/var/run/docker.sock # Localhost docker socket accessed through dockerproxy
    environment:
      - READONLY_MODE=false  # Set to true for view-only access
      - DOCKER_HOSTS=Krusty=tcp://127.0.0.1:2375,Photos=tcp://10.8.0.2:2375

  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:15
    container_name: wg-easy
    networks:
      wg:
        ipv4_address: 10.42.42.42
      default:
    volumes:
      - ./etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    ports:
      - "51822:51822/udp"
      #- "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      #- net.ipv6.conf.all.disable_ipv6=0
      #- net.ipv6.conf.all.forwarding=1
      #- net.ipv6.conf.default.forwarding=1
    environment:
      - DISABLE_IPV6=true

  dockerproxy:
    image: ghcr.io/tecnativa/docker-socket-proxy:latest
    container_name: dockerproxy
    network_mode: "container:wg-easy"
    environment:
      - BIND=127.0.0.1 # Because dockerproxy shares the wg-easy namespace restricting it to localhost so WG peers can't reach it
      - AUTH=0 # Considered security-critical.  Disabled
      - CONTAINERS=1 # Allow access to viewing containers
      - POST=1 # Set to 0 to disallow any POST operations (effectively read-only - Only GET and HEAD operations are allowed)
      - BUILD=0
      - COMMIT=1
      - CONFIGS=1
      - DISTRIBUTION=1
      - EXEC=0
      - IMAGES=1
      - INFO=1
      - NETWORKS=1
      - NODES=1
      - PLUGINS=1
      - SERVICES=1
      - SESSION=1
      - SECRETS=0 # Considered security-critical.  Disabled
      - SWARM=0
    #ports:
    #  - "10.8.0.2:2375:2375" # Port is accessible through the wg-easy container
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
```
