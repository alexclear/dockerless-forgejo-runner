#!/bin/bash
set -e

podman system service -t 0 > /dev/stdout 2>&1 &
PODMAN_PID=$!

# Wait for socket
SOCK="/tmp/podman-run-1001/podman/podman.sock"
for i in {1..10}; do
    if [ -S "$SOCK" ]; then
        break
    fi
    echo "Waiting for the Podman socket to appear"
    sleep 1
done

# Start Forgejo runner
export DOCKER_HOST="unix://${SOCK}"
./forgejo-runner register --no-interactive --token "${FORGEJO_TOKEN}" --instance "${FORGEJO_URL}"

# Wait for both processes (podman + runner)
./forgejo-runner daemon > /dev/stdout 2>&1 &

wait -n $PODMAN_PID
