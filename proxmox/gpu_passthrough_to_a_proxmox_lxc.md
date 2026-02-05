# GPU Passthrough to a Proxmox LXC (including docker)

## References:

- [XDA Developers: Nvidia stopped supporting my GPU, so I started self-hosting LLMs with it](https://www.xda-developers.com/nvidia-stopped-supporting-my-gpu-so-i-started-self-hosting-llms-with-it/) - I admit, most of this article is directly lifted from this source, but I've updated it based on my own experience, added the bits on docker passthrough and am storing it for my own reference.
- [Installing the NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#installation) - these are the instructions direct from NVIDIA to install the NVIDIA Container Toolkit which enables passthough of the GPU to docker containers (I've only included the Ubuntu/Debian instructions as that's what I'm using)

## Introduction

If you’ve been rocking a Pascal GPU, you may have heard about Nvidia finally pulling the plug on new drivers for the 10-series cards. As someone with a perfectly fine GTX 1080 Ti, I wasn’t too thrilled about this news. Sure, it may not be able to deliver ultra-high frame rates at 4K or process ray-traced graphics, but it’s more than capable of rendering several games in my library at playable frame rates – and it can even push upwards of 1440p in most indie titles.

I’ve got an entire home lab built from old nodes, so there was no way I’d toss my faithful companion away just because it won’t receive optimizations for new games. With a little bit of tinkering and lots of troubleshooting, I configured my GTX 1080 to host LLMs via a docker running inside a LXC running on a Proxmox node.

## Why a LXC

I have several uses for my graphics card.  It might not be good enough for the latest games, but I'm not a gamer so that doesn't really interest me; however I'm really interested in playing with some LLMs and I have video transcoding needs.
The i5-10500 driving my Proxmox server has an iGPU that does a great job of transcoding videos for Jellyfin playback, but it doesn't do so well if I want to run bulk transcoding tasks using [Tdarr](https://home.tdarr.io/).  Additionally, as soon as I plugged in my GCT 1080, the iGPU was disabled so I was back to CPU transcoding even in Jellyfin!

Given that I've got several different uses for the GPU, I really didn't want to limit myself to one container - this ruled out using VMs:  VMs use dedicated resources (i.e. you can only passthrough a GPU to a single VM), LXCs share resources (you can passthrough the same GPU to multiple LXCs which share the resource).

## Proxmox Drivers

So, the first order of business was to install the right Nvidia drivers on the Proxmox rig. But since Team Green removed support for Pascal cards with 590.48.01, I went with 580.119.02 instead. But as with everything Nvidia-related, the installation process was a convoluted mess but here’s a brief overview of the whole process:

1. I ran `nano /etc/modprobe.d/blacklist-nouveau.conf` in my main node file to blacklist the Nvidia GPU. This involved pasting the following code into the file and hitting Ctrl+Shift+X to save and Y to head back to the Proxmox Shell.

>### Note
>
> All the commands in this article need to be run as `sudo`

```bash
blacklist nouveau
options nouveau modeset=0
```
2. Then, I ran `rmmod nouveau` to delete any existing nouveau drivers on my PVE node.
3. Before downloading the old Nvidia drivers, I ran the `apt install build-essential pve-headers-$(uname -r)` command to grab the packages needed to execute them.
4. After that, I ran `wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.119.02/NVIDIA-Linux-x86_64-580.119.02.run` to pull the drivers onto my PVE host
5. I used `chmod +x NVIDIA-Linux-x86_64-580.119.02.run` to make it executable, and
6. Enter `./NVIDIA-Linux-x86_64-580.119.02.run` to initiate the installation wizard.

With all this done, you can run `nvidia-smi` to confirm the GPU has been detected

```bash
# nvidia-smi
Thu Feb  5 14:36:17 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.119.02             Driver Version: 580.119.02     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce GTX 1080 Ti     Off |   00000000:01:00.0 Off |                  N/A |
| 56%   71C    P2            105W /  250W |    2468MiB /  11264MiB |     42%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A         1051549      C   tdarr-ffmpeg                            492MiB |
|    0   N/A  N/A         1053728      C   tdarr-ffmpeg                            492MiB |
|    0   N/A  N/A         1055701      C   tdarr-ffmpeg                            492MiB |
|    0   N/A  N/A         1065692      C   tdarr-ffmpeg                            492MiB |
|    0   N/A  N/A         1066133      C   tdarr-ffmpeg                            492MiB |
+-----------------------------------------------------------------------------------------+
```

## LXC Drivers

>### Note
>
> I am not saying this is the best way to passthough a GPU to LXCs, or even that it's correct or secure. I'm just documenting what worked for me.  I'd welcome comments if there's a better way of doing this

I have existing privileged LXCs that I want to pass the GPU through to.  They are all basedon Debian 12.

7. Still on the Proxmox host, I ran `ls -l /dev/nvidia*` to identify the device number associated with the GPU components.  In my particular setup, this is the result:

```bash
# ls -l /dev/nvidia*
crw-rw-rw- 1 root root 195,   0 Feb  3 17:57 /dev/nvidia0
crw-rw-rw- 1 root root 195, 255 Feb  3 17:57 /dev/nvidiactl
crw-rw-rw- 1 root root 506,   0 Feb  3 17:57 /dev/nvidia-uvm
crw-rw-rw- 1 root root 506,   1 Feb  3 17:57 /dev/nvidia-uvm-tools

/dev/nvidia-caps:
total 0
cr-------- 1 root root 509, 1 Feb  3 17:57 nvidia-cap1
cr--r--r-- 1 root root 509, 2 Feb  3 17:57 nvidia-cap2
```
Make a note of these numbers in your setup - you'll need them later

8.  On the Proxmox host I executed the nano `/etc/pve/lxc/206.conf` command to open the configuration file for my LXC and added the following lines of code to mount the GPU onto the container and tweak the permissions to let Ollama call upon it when running LLMs

```bash
features: nesting=1,fuse=1,keyctl=1
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 195:255 rwm
lxc.cgroup2.devices.allow: c 506:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
```

9. With the tweaks on the PVE host complete, I started the LXC and ran `apt update && apt upgrade` to install the latest packages. 
10. Then, I ran the same set of commands to install Nvidia drivers on the LXC. The only difference was the --no-kernel-modules argument when running the executable, as the installation would fail if I didn’t add it.

```bash
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.119.02/NVIDIA-Linux-x86_64-580.119.02.run
chmod +x NVIDIA-Linux-x86_64-580.119.02.run
./NVIDIA-Linux-x86_64-580.119.02.run --no-kernel-modules
```

11. I ran nvidia-smi inside the LXC, and the same monitoring UI as earlier popped up confirming the GPU is now available inside the LXC

## Docker Drivers

Inside my LXCs, I run everything in Docker, so the next stage is to make the GPUs available to Docker:

>### Note
>
> There is a known issue on systems where `systemd` cgroup drivers are used that cause containers to lose access to requested GPUs when `systemctl daemon reload` is run. Refer to the troubleshooting documentation for more information.

### With `apt`: Ubuntu, Debian

>### Note
>
> These instructions should work for any Debian-derived distribution.

12. Install the prerequisites for the instructions below:

```bash
apt-get update && sudo apt-get install -y --no-install-recommends \
 curl \
 gnupg2
```

13. Configure the production repository:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

14. Optionally, configure the repository to use experimental packages **(I didn't do this)**:

sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

Update the packages list from the repository:

sudo apt-get update

Install the NVIDIA Container Toolkit packages:

export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.2-1
  sudo apt-get install -y \
      nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
      libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}


