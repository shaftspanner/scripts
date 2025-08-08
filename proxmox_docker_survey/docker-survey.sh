#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 [-o output_directory]"
    echo "  -o   Specify output directory for markdown files (default: /root/proxmox-docker-md)"
    echo "  -h   Show this help message"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Default output directory
OUTPUT_DIR="/root/proxmox-docker-md"

# Parse options
while getopts ":o:h" opt; do
    case $opt in
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

echo "Saving markdown files to output directory: $OUTPUT_DIR"
echo "Scanning running LXC containers for Docker..."

# Current date for file creation property
CURRENT_DATE=$(date +%F)

sanitize_name() {
    local raw="$1"
    local sanitized
    sanitized=$(echo "$raw" | sed -E 's/[^a-zA-Z0-9]+/_/g')
    sanitized=$(echo "$sanitized" | sed -E 's/^_+|_+$//g')
    echo "$sanitized"
}

RUNNING_LXCS=$(pct list | awk 'NR>1 && $2=="running" {print $1}')

declare -A NAME_COUNT

# First pass: count container names per LXC hostname
for LXC_ID in $RUNNING_LXCS; do
    LXC_HOSTNAME=$(pct exec $LXC_ID -- hostname 2>/dev/null || echo "Unknown")
    SAFE_HOSTNAME=$(sanitize_name "$LXC_HOSTNAME")

    if ! pct exec $LXC_ID -- test -S /var/run/docker.sock; then
        echo "No Docker socket in LXC $LXC_ID, skipping container name count."
        continue
    fi

    CONTAINERS=$(pct exec $LXC_ID -- docker ps -q)
    if [[ -z "$CONTAINERS" ]]; then
        echo "No running Docker containers in LXC $LXC_ID"
        continue
    fi

    for CONTAINER_ID in $CONTAINERS; do
        DOCKER_NAME=$(pct exec $LXC_ID -- docker inspect --format='{{.Name}}' "$CONTAINER_ID" | sed 's|/||')
        SERVICE_NAME=$(pct exec $LXC_ID -- docker inspect --format='{{index .Config.Labels "com.docker.compose.service"}}' "$CONTAINER_ID")

        if [[ -n "$DOCKER_NAME" ]]; then
            CONTAINER_NAME="$DOCKER_NAME"
        elif [[ -n "$SERVICE_NAME" && "$SERVICE_NAME" != "<no value>" ]]; then
            CONTAINER_NAME="$SERVICE_NAME"
        else
            CONTAINER_NAME="unknown-container"
        fi

        SAFE_NAME=$(sanitize_name "$CONTAINER_NAME")
        KEY="${SAFE_HOSTNAME}|${SAFE_NAME}"

        if [[ -v NAME_COUNT["$KEY"] ]]; then
            (( NAME_COUNT["$KEY"]++ ))
        else
            NAME_COUNT["$KEY"]=1
        fi
    done
done

# Second pass: generate markdown files with unique suffixes if duplicates
for LXC_ID in $RUNNING_LXCS; do
    echo "Checking LXC $LXC_ID..."

    LXC_HOSTNAME=$(pct exec $LXC_ID -- hostname 2>/dev/null || echo "Unknown")
    SAFE_HOSTNAME=$(sanitize_name "$LXC_HOSTNAME")

    if ! pct exec $LXC_ID -- test -S /var/run/docker.sock; then
        echo "No Docker socket in LXC $LXC_ID, skipping."
        continue
    fi

    CONTAINERS=$(pct exec $LXC_ID -- docker ps -q)
    if [[ -z "$CONTAINERS" ]]; then
        echo "No running Docker containers in LXC $LXC_ID"
        continue
    fi

    declare -A NAME_SEEN=()

    for CONTAINER_ID in $CONTAINERS; do
        DOCKER_NAME=$(pct exec $LXC_ID -- docker inspect --format='{{.Name}}' "$CONTAINER_ID" | sed 's|/||')
        SERVICE_NAME=$(pct exec $LXC_ID -- docker inspect --format='{{index .Config.Labels "com.docker.compose.service"}}' "$CONTAINER_ID")

        if [[ -n "$DOCKER_NAME" ]]; then
            CONTAINER_NAME="$DOCKER_NAME"
        elif [[ -n "$SERVICE_NAME" && "$SERVICE_NAME" != "<no value>" ]]; then
            CONTAINER_NAME="$SERVICE_NAME"
        else
            CONTAINER_NAME="unknown-container"
        fi

        IMAGE=$(pct exec $LXC_ID -- docker inspect --format='{{.Config.Image}}' "$CONTAINER_ID")
        STATE=$(pct exec $LXC_ID -- docker inspect --format='{{.State.Status}}' "$CONTAINER_ID")
        CREATED=$(pct exec $LXC_ID -- docker inspect --format='{{.Created}}' "$CONTAINER_ID")
        CMD=$(pct exec $LXC_ID -- docker inspect --format='{{json .Config.Cmd}}' "$CONTAINER_ID" | tr -d '[]"')

        PORTS=$(pct exec $LXC_ID -- docker port "$CONTAINER_ID" 2>/dev/null)
        if [[ -z "$PORTS" ]]; then
            PORTS="None"
        else
            PORTS=$(echo "$PORTS" | sed ':a;N;$!ba;s/\n/, /g')
        fi

        MOUNTS=$(pct exec $LXC_ID -- docker inspect --format='{{range .Mounts}}{{.Source}}:{{.Destination}}{{if ne .RW true}}:ro{{end}}, {{end}}' "$CONTAINER_ID" | sed 's/, $//')
        if [[ -z "$MOUNTS" ]]; then
            MOUNTS="None"
        fi

        LABELS_RAW=$(pct exec $LXC_ID -- docker inspect --format='{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}
{{end}}' "$CONTAINER_ID" | sed '/^\s*$/d')
        if [[ -z "$LABELS_RAW" ]]; then
            LABELS="None"
        else
            LABELS=$(echo "$LABELS_RAW" | sed ':a;N;$!ba;s/\n/, /g')
        fi

        DEPENDS_ON_LABEL=$(pct exec $LXC_ID -- docker inspect --format='{{index .Config.Labels "com.docker.compose.depends_on"}}' "$CONTAINER_ID")
        if [[ -z "$DEPENDS_ON_LABEL" || "$DEPENDS_ON_LABEL" == "<no value>" ]]; then
            DEPENDS_ON="None"
        else
            DEPENDS_ON="$DEPENDS_ON_LABEL"
        fi

        SAFE_NAME=$(sanitize_name "$CONTAINER_NAME")
        KEY="${SAFE_HOSTNAME}|${SAFE_NAME}"

        COUNT=${NAME_COUNT[$KEY]}
        if [[ "$COUNT" -gt 1 ]]; then
            if [[ -v NAME_SEEN["$KEY"] ]]; then
                (( NAME_SEEN["$KEY"]++ ))
            else
                NAME_SEEN["$KEY"]=1
            fi
            # Add suffix only from second occurrence onward (_1 for second instance)
            if [[ "${NAME_SEEN[$KEY]}" -eq 1 ]]; then
                SUFFIX=""
            else
                SUFFIX="_$(( NAME_SEEN[$KEY] - 1 ))"
            fi
        else
            SUFFIX=""
        fi

        MD_FILE="$OUTPUT_DIR/${SAFE_HOSTNAME}_${SAFE_NAME}${SUFFIX}.md"

        echo "Creating markdown for container '$CONTAINER_NAME' ($CONTAINER_ID) in LXC $LXC_ID as file: $(basename "$MD_FILE")"

        cat > "$MD_FILE" <<EOF
---
MOC: "[[Servers#Services]]"
aliases:
template: Services
version: 1
date_created: $CURRENT_DATE
last_update: $CURRENT_DATE
type: service
lxc_id: $LXC_ID
server: $LXC_HOSTNAME
container: $CONTAINER_NAME
container_id: $CONTAINER_ID
container_created: $CREATED
image: $IMAGE
state: $STATE
command: $CMD
ports: $PORTS
mounts: $MOUNTS
labels: $LABELS
depends_on: $DEPENDS_ON
---
# Docker Container: $CONTAINER_NAME
- **Container ID:** $CONTAINER_ID
- **Image:** $IMAGE
- **State:** $STATE
- **Created:** $CREATED
- **Command:** $CMD
- **Ports:** $PORTS
- **Mounts:** $MOUNTS
- **Labels:** $LABELS
- **Depends On:** $DEPENDS_ON
- **LXC Hostname:** $LXC_HOSTNAME
- **File Created:** $CURRENT_DATE

# Compose
\`\`\`yaml
\`\`\`
# .env
\`\`\`yaml
\`\`\`

---
# References
EOF

    done

    unset NAME_SEEN
done

echo "Done. Markdown files saved in $OUTPUT_DIR"
