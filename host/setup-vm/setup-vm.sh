#!/usr/bin/env bash
set -euo pipefail

VM_NAME="clever-computer"
IMAGE="ghcr.io/cirruslabs/macos-sequoia-xcode:latest"
DEFAULT_USER="admin"
DEFAULT_PASS="admin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  echo "Copy config.sh.template to config.sh and fill in your SSH public key path."
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

SSH_PUB_KEY="$SSH_PUBLIC_KEY_PATH"

if [[ -z "$SSH_PUB_KEY" ]]; then
  echo "Error: SSH_PUBLIC_KEY_PATH is not set in $CONFIG_FILE"
  exit 1
fi

if [[ ! -f "$SSH_PUB_KEY" ]]; then
  echo "Error: SSH public key file not found: $SSH_PUB_KEY"
  exit 1
fi

echo "Using SSH public key: $SSH_PUB_KEY"
SANDBOX_SCRIPT="$SCRIPT_DIR/../../sandbox/setup-vm/provision.sh"
CA_CERT="$SCRIPT_DIR/../github-proxy/certs/ca.crt"

if [[ ! -f "$CA_CERT" ]]; then
  echo "Certificates not found, generating..."
  "$SCRIPT_DIR/../github-proxy/generate-certs.sh" "$SCRIPT_DIR/../github-proxy/certs"
fi

# Pull the image if not already present
if ! tart list | grep -q "$IMAGE"; then
  echo "Pulling $IMAGE..."
  tart pull "$IMAGE"
else
  echo "Image $IMAGE already present."
fi

# Clone the VM if it doesn't already exist
if tart list | grep -q "$VM_NAME"; then
  echo "VM '$VM_NAME' already exists."
else
  echo "Cloning $IMAGE as $VM_NAME..."
  tart clone "$IMAGE" "$VM_NAME"
fi

# Start the VM headless in the background
echo "Starting VM '$VM_NAME' headless..."
tart run "$VM_NAME" --no-graphics --net-softnet &
TART_PID=$!

# Wait for the VM to boot and get its IP
echo "Waiting for VM to boot..."
VM_IP=""
for _i in $(seq 1 60); do
  VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
  if [[ -n "$VM_IP" ]]; then
    break
  fi
  sleep 5
done

if [[ -z "$VM_IP" ]]; then
  echo "Error: Timed out waiting for VM IP."
  kill "$TART_PID" 2>/dev/null || true
  exit 1
fi

echo "VM is up at $VM_IP"

# Wait a bit more for SSH to be ready
echo "Waiting for SSH to become available..."
for _i in $(seq 1 30); do
  if sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$DEFAULT_USER@$VM_IP" "echo ok" &>/dev/null; then
    break
  fi
  sleep 2
done

# Inject the SSH public key
echo "Injecting SSH public key..."
PUB_KEY_CONTENT=$(cat "$SSH_PUB_KEY")
sshpass -p "$DEFAULT_PASS" ssh "$DEFAULT_USER@$VM_IP" \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_KEY_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Copy and run the sandbox setup script
echo "Copying sandbox setup script to VM..."
scp "$SANDBOX_SCRIPT" "$DEFAULT_USER@$VM_IP:/tmp/setup-vm.sh"

echo "Copying CA certificate to VM..."
scp "$CA_CERT" "$DEFAULT_USER@$VM_IP:/tmp/github-proxy-ca.crt"

echo "Running sandbox setup script..."
# We intentionally expand $VM_NAME client-side
# shellcheck disable=SC2029
ssh "$DEFAULT_USER@$VM_IP" "bash /tmp/setup-vm.sh $VM_NAME"

echo "Applying configuration..."
"$SCRIPT_DIR/apply-config"

echo ""
echo "VM '$VM_NAME' is running at $VM_IP (PID: $TART_PID)"
echo "Connect with:"
echo "  ssh $DEFAULT_USER@$VM_IP"
