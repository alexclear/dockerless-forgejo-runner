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

# --- storage config files ---
KERNEL_STORAGE_CONF=/etc/containers/storage-koverlay.conf
FUSE_STORAGE_CONF=/etc/containers/storage-fuse.conf

# Prefer kernel overlayfs (no mount_program!)
cat >"$KERNEL_STORAGE_CONF" <<'EOF'
[storage]
driver = "overlay"
runroot = "/var/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options.overlay]
mountopt = "metacopy=on"
EOF

# Explicit FUSE fallback (only if kernel overlay fails)
cat >"$FUSE_STORAGE_CONF" <<'EOF'
[storage]
driver = "overlay"
runroot = "/var/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Tell Podman exactly which config to use:
export CONTAINERS_STORAGE_CONF="$KERNEL_STORAGE_CONF"

# (Optional but helpful) quick kernel overlay presence hint
grep -q overlay /proc/filesystems || true

# Start podman service with kernel overlay config
podman --log-level=debug system service -t 0 > /dev/stdout 2>&1 &
PODMAN_PID=$!

# Wait for socket
SOCK="/run/podman/podman.sock"
for i in {1..20}; do
  [ -S "$SOCK" ] && break
  sleep 0.5
done

# Verify kernel overlay actually active; else switch to FUSE once
#if ! podman info 2>/dev/null | grep -q 'Native Overlay Diff: "true"'; then
#  echo "Kernel overlayfs not active -> switching to fuse-overlayfs"
#  kill "$PODMAN_PID" || true
#  export CONTAINERS_STORAGE_CONF="$FUSE_STORAGE_CONF"
#  podman --log-level=debug system service -t 0 > /dev/stdout 2>&1 &
#  PODMAN_PID=$!
#fi

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
