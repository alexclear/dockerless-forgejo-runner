#!/bin/bash
set -euxo pipefail

echo "Entrypoint started as user: $(id -u):$(id -g), pwd: $PWD"

# Generate default config if it doesn't exist
CONFIG="config.yml"
if [[ ! -f "$CONFIG" ]]; then
    echo "Generating Forgejo runner config..."
    ./forgejo-runner generate-config > "$CONFIG"
fi

# Patch config.yml: set container.valid_volumes to ["**"]
yq -i -y '.container.valid_volumes = ["**"]' "$CONFIG"
yq -i -y '.runner.labels |= ( (. // []) + ["self-hosted:host://-", "docker:docker://node:20-bullseye"] | unique )' "$CONFIG"

echo "Final runner config:"
cat "$CONFIG"

# Write a kernel-overlay-first config
cat >/etc/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
runroot = "/var/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options.overlay]
# big wins for metadata-heavy workloads
mountopt = "metacopy=on"
# optional: add ",volatile" for even more speed (accept crash-recovery risk in CI)
# mountopt = "metacopy=on,volatile"
EOF

# Try kernel overlayfs; if unavailable, fall back to fuse-overlayfs
if ! podman info --format '{{.Store.GraphOptions}} {{.Store.GraphDriverName}} {{.Store.GraphStatus}}' 2>/dev/null | grep -q 'Native Overlay Diff: "true"'; then
  echo "Kernel overlayfs not available, switching to fuse-overlayfs..."
  cat >/etc/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
runroot = "/var/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
fi

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
