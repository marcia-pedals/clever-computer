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

# The host IP is the default gateway on the softnet VM network
HOST_IP=$(route -n get default | awk '/gateway:/ {print $2}')
echo "Adding github.proxy → $HOST_IP to /etc/hosts..."
echo "$HOST_IP github.proxy" | sudo tee -a /etc/hosts > /dev/null

echo "Configuring git identity..."
git config --global user.name "clever-computer[bot]"
git config --global user.email "clever-computer[bot]@users.noreply.github.com"
git config --global --replace-all credential.helper ""

echo "Configuring git to use GitHub proxy..."
# Embed dummy credentials in the URL so git never prompts — the proxy injects the real token.
git config --global url."https://x-access-token:proxy-managed@github.proxy:8443/".insteadOf "https://github.proxy:8443/"
git config --global http."https://github.proxy:8443".sslCAInfo /usr/local/share/ca-certificates/github-proxy-ca.crt

# Install Claude Code
curl -fsSL https://claude.ai/install.sh | bash
echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.zshrc

# Install gh CLI via Nix
echo "Installing gh CLI..."
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix profile add nixpkgs#gh

# Configure gh to use the GitHub proxy (treated as a GitHub Enterprise host).
# The proxy injects auth tokens, so the token here is a placeholder.
echo "Configuring gh to use GitHub proxy..."
mkdir -p ~/.config/gh
cat > ~/.config/gh/hosts.yml << 'EOF'
github.proxy:8443:
    oauth_token: proxy-managed
    git_protocol: https
EOF
cat >> ~/.zshenv << 'EOF'
export GH_HOST=github.proxy:8443
EOF

# Install direnv
echo "Installing direnv..."
nix profile add nixpkgs#direnv
cat >> ~/.zshrc << 'EOF'
eval "$(direnv hook zsh)"
EOF
