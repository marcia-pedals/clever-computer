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

# Set environment variables for future login sessions
echo "Configuring environment variables..."
echo 'export EXAMPLE_ENV=hello-world' >> ~/.zshenv

# Add ~/scripts to PATH
# shellcheck disable=SC2016
echo 'export PATH="$HOME/scripts:$PATH"' >> ~/.zshenv

# Install Nix
echo "Installing Nix..."
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

# Configure GitHub proxy
if [[ ! -f /tmp/github-proxy-ca.crt ]]; then
  echo "Error: CA certificate not found at /tmp/github-proxy-ca.crt"
  exit 1
fi

# Copy the CA cert to a persistent location (out of /tmp).
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

echo "Configuring git identity..."
git config --global user.name "clever-computer[bot]"
git config --global user.email "clever-computer[bot]@users.noreply.github.com"
git config --global --replace-all credential.helper ""

echo "Configuring git to use GitHub proxy..."
# Embed dummy credentials in the URL so git never prompts — the proxy injects the real token.
git config --global url."https://x-access-token:proxy-managed@github.proxy/".insteadOf "https://github.proxy/"
git config --global http."https://github.proxy".sslCAInfo /usr/local/share/ca-certificates/github-proxy-ca.crt

# Install Claude Code
curl -fsSL https://claude.ai/install.sh | bash
echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.zshrc
# shellcheck disable=SC2016
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# Install gh CLI and socat via Nix
echo "Installing gh CLI and socat..."
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix profile add nixpkgs#gh nixpkgs#socat

# Configure gh to use the GitHub proxy (treated as a GitHub Enterprise host).
# The proxy injects auth tokens, so the token here is a placeholder.
echo "Configuring gh to use GitHub proxy..."
cat >> ~/.zshenv << 'EOF'
export GH_HOST=github.proxy
EOF

# Port-forward github.proxy:443 → host:8443 so gh CLI works (gh doesn't
# support non-standard ports). Runs as a system-level launchd daemon so it
# survives across login sessions and starts on boot.
echo "Setting up port forward (443 → $HOST_IP:8443)..."
SOCAT_PATH=$(which socat)
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

# Install direnv
echo "Installing direnv..."
nix profile add nixpkgs#direnv
cat >> ~/.zshrc << 'EOF'
eval "$(direnv hook zsh)"
EOF
