#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOSTNAME="$1"

# Set hostname
echo "Setting hostname to '$HOSTNAME'..."
sudo scutil --set HostName "$HOSTNAME"
sudo scutil --set LocalHostName "$HOSTNAME"
sudo scutil --set ComputerName "$HOSTNAME"

# Install Nix
echo "Installing Nix..."
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Configure GitHub proxy CA certificate
if [[ ! -f /tmp/github-proxy-ca.crt ]]; then
  echo "Error: CA certificate not found at /tmp/github-proxy-ca.crt"
  exit 1
fi

sudo mkdir -p /usr/local/share/ca-certificates
sudo cp /tmp/github-proxy-ca.crt /usr/local/share/ca-certificates/github-proxy-ca.crt

echo "Installing GitHub proxy CA certificate..."
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /usr/local/share/ca-certificates/github-proxy-ca.crt

# The host IP is the default gateway on the softnet VM network.
# github.proxy resolves to localhost; socat forwards 443 → host:8443.
HOST_IP=$(route -n get default | awk '/gateway:/ {print $2}')
echo "Adding github.proxy → 127.0.0.1 to /etc/hosts..."
echo "127.0.0.1 github.proxy" | sudo tee -a /etc/hosts > /dev/null

# Port-forward github.proxy:443 → host:8443 so gh CLI works (gh doesn't
# support non-standard ports). Runs as a system-level launchd daemon so it
# survives across login sessions and starts on boot.
# Build socat into the nix store (without adding to nix profile, which would
# conflict with home-manager) so we can reference a stable path in the plist.
echo "Building socat for port forwarding..."
SOCAT_PATH="$(nix build nixpkgs#socat --no-link --print-out-paths)/bin/socat"

echo "Setting up port forward (443 → $HOST_IP:8443)..."
sudo tee /Library/LaunchDaemons/com.clever-computer.github-proxy-forward.plist > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clever-computer.github-proxy-forward</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SOCAT_PATH</string>
        <string>TCP-LISTEN:443,fork,reuseaddr</string>
        <string>TCP:$HOST_IP:8443</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
sudo launchctl load /Library/LaunchDaemons/com.clever-computer.github-proxy-forward.plist

# Install Claude Code
echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Apply declarative user config via Home Manager.
# Remove the base image's default ~/.gitconfig so it doesn't shadow the
# Home Manager config at ~/.config/git/config (git prefers ~/.gitconfig).
rm -f ~/.gitconfig
echo "Applying Home Manager configuration..."
nix run home-manager -- switch --flake ~/home-config
