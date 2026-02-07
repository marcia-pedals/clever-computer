#!/usr/bin/env bash
set -euo pipefail

VM_NAME="clever-computer"
TEST_REPO="marcia-pedals/clever-computer-test"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
PROXY_DIR="$ROOT_DIR/host/github-proxy"
CERT_DIR="$PROXY_DIR/certs"
SETUP_VM="$ROOT_DIR/host/setup-vm/setup-vm.sh"
SANDBOX_TEST="$ROOT_DIR/sandbox/tests/test-gh-integration.sh"

DEFAULT_USER="admin"

PROXY_PID=""

cleanup() {
  echo ""
  echo "=== Cleaning up ==="

  if [[ -n "$PROXY_PID" ]]; then
    echo "Stopping GitHub proxy (PID $PROXY_PID)..."
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
  fi

  if tart list 2>/dev/null | grep -q "$VM_NAME"; then
    echo "Stopping and deleting VM '$VM_NAME'..."
    tart stop "$VM_NAME" 2>/dev/null || true
    tart delete "$VM_NAME" 2>/dev/null || true
  fi
}

trap cleanup EXIT

# --- Cleanup any pre-existing state ---
echo "=== Pre-flight cleanup ==="
if tart list 2>/dev/null | grep -q "$VM_NAME"; then
  echo "Removing existing VM '$VM_NAME'..."
  tart stop "$VM_NAME" 2>/dev/null || true
  tart delete "$VM_NAME" 2>/dev/null || true
fi

if [[ -d "$CERT_DIR" ]]; then
  echo "Removing existing certificates..."
  rm -rf "$CERT_DIR"
fi

# --- Generate fresh certificates ---
echo ""
echo "=== Generating certificates ==="
"$PROXY_DIR/generate-certs.sh" "$CERT_DIR"

# --- Start the GitHub proxy ---
echo ""
echo "=== Building and starting GitHub proxy ==="
PROXY_BIN=$(mktemp)
(cd "$PROXY_DIR" && go build -o "$PROXY_BIN" .)
(cd "$PROXY_DIR" && "$PROXY_BIN") &
PROXY_PID=$!

# Give the proxy a moment to start
sleep 3

if ! kill -0 "$PROXY_PID" 2>/dev/null; then
  echo "Error: GitHub proxy failed to start."
  exit 1
fi
echo "GitHub proxy running (PID $PROXY_PID)"

# --- Provision the VM ---
echo ""
echo "=== Setting up VM ==="
"$SETUP_VM" ~/.ssh/id_ed25519.pub

VM_IP=$(tart ip "$VM_NAME")
echo "VM IP: $VM_IP"

# --- Copy and run the sandbox test ---
echo ""
echo "=== Copying test script to VM ==="
scp "$SANDBOX_TEST" "$DEFAULT_USER@$VM_IP:/tmp/test-gh-integration.sh"

echo ""
echo "=== Running integration tests ==="
# shellcheck disable=SC2029
ssh "$DEFAULT_USER@$VM_IP" "bash /tmp/test-gh-integration.sh $TEST_REPO"

echo ""
echo "=== All integration tests passed ==="
