#!/bin/bash
set -euxo pipefail

echo "Entrypoint started as user: $(id -u):$(id -g), pwd: $PWD"

# Generate default config if it doesn't exist
CONFIG="config.yml"
if [[ ! -f "$CONFIG" ]]; then
    echo "Generating Forgejo runner config..."
    ./forgejo-runner generate-config > "$CONFIG"
fi

# Patch valid_volumes to allow all
if ! grep -q 'valid_volumes:' "$CONFIG"; then
    echo "valid_volumes: ['**']" >> "$CONFIG"
elif ! grep -q "'\*\*'" "$CONFIG"; then
    # If valid_volumes exists but doesn't allow all, patch it in-place (yq preferred, else sed/hack)
    sed -i '/valid_volumes:/c\valid_volumes:\n  - '\''**'\''' "$CONFIG"
fi

echo "Final runner config:"
cat "$CONFIG"

# Start podman system service in debug mode
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

# Start Forgejo runner registration with the custom config
export DOCKER_HOST="unix://${SOCK}"
./forgejo-runner register --no-interactive --token "${FORGEJO_TOKEN}" --instance "${FORGEJO_URL}" --config "$CONFIG" || { echo "Runner registration failed!"; exit 1; }

# Start Forgejo runner daemon in background with custom config
./forgejo-runner daemon --config "$CONFIG" > /dev/stdout 2>&1 &
RUNNER_PID=$!

echo "PIDs: podman=$PODMAN_PID runner=$RUNNER_PID"

# Wait for any process to exit and print status
wait -n $PODMAN_PID $RUNNER_PID
STATUS=$?
echo "Entrypoint exiting, status $STATUS"
exit $STATUS
