# Proxmox Docker Survey

## Introduction

A bash script written largely by ChatGPT to survey all running LXCs on a Proxmox server and generate a md file compatible with Obsidian for each running docker container.

Tested on Proxmox 8.4.8

## AI Prompt (gpt-4.1-mini)

write a bash script for use with proxmox.  
- The script should query each running lxc on the proxmox system.
- If there is a running docker socket in that lxc, the script should create a markdown file for each running docker container; the markdown file will be viewed in Obsidian
- Filename should be .md - all of the containers should have the container name set within the docker compose, but the script should be able to fall back to the service name if a container name isn’t specified
- Set the name of the markdowns to <LXC-hostname>_<container-name>.md
- include a unique suffix to the filenames if (and only if) there is more than container with the same name in the same LXC hostname
- Allow the user to specify a custom output directory parameter
- check that the script is being run as root
- Include a property for any depends-on relationships
- Include a property for the date the file has been created in the format “yyyy-mm-dd”
- Include a property for the hostname of the LXC that the container is running on

## Instructions

- Save as e.g. `proxmox-docker-lxc-md.sh`.
- Make executable: `chmod +x proxmox-docker-lxc-md.sh`.
- Run with default output directory:

```bash
sudo ./proxmox-docker-lxc-md.sh
``` 
Or specify custom output directory:
```bash
sudo ./proxmox-docker-lxc-md.sh -o /path/to/output/dir
``` 
