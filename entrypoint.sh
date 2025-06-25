#!/bin/bash
set -e

# Start Podman system service in the background
podman system service -t 0 &

# Wait for the Podman socket to be available
SOCK="$XDG_RUNTIME_DIR/podman/podman.sock"
for i in {1..10}; do
    if [ -S "$SOCK" ]; then
        break
    fi
    sleep 1
done

# Start Forgejo runner daemon, using Podman socket
export DOCKER_HOST="unix://${SOCK}"
exec ./forgejo-runner daemon
