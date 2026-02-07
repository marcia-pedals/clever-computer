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

# Install Nix
echo "Installing Nix..."
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
