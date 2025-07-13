#!/bin/bash
set -euxo pipefail

echo "Entrypoint started as user: $(id -u):$(id -g), pwd: $PWD"

# Launch podman system service in debug mode
podman --log-level=debug system service -t 0 > /dev/stdout 2>&1 &
PODMAN_PID=$!

# Wait for podman socket (use correct path)
SOCK="/run/podman/podman.sock"
for i in {1..10}; do
    if [ -S "$SOCK" ]; then
        echo "Found podman socket at $SOCK"
        break
    fi
    echo "Waiting for the Podman socket to appear at $SOCK"
    sleep 1
done

# Start Forgejo runner registration
export DOCKER_HOST="unix://${SOCK}"
./forgejo-runner register --no-interactive --token "${FORGEJO_TOKEN}" --instance "${FORGEJO_URL}" || { echo "Runner registration failed!"; exit 1; }

# Start Forgejo runner daemon in background
./forgejo-runner daemon > /dev/stdout 2>&1 &
RUNNER_PID=$!

echo "PIDs: podman=$PODMAN_PID runner=$RUNNER_PID"

# Wait for any process to exit and print status
wait -n $PODMAN_PID $RUNNER_PID
STATUS=$?
echo "Entrypoint exiting, status $STATUS"
exit $STATUS
