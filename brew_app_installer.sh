#!/bin/bash
set -e
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not installed. See https://brew.sh"
  exit 1
fi

echo "Updating Homebrew..."
brew update

# Casks to install
CASKS=(
  "breaktimer"
  "do-not-disturb"
  "network-radar"
  "nzbget"
  "ollama"
  "switchresx"
  "tailscale"
  "timer"
  "whatsapp"
  "zoom"
  "applite"
)

echo "Installing casks: ${CASKS[*]}"
for c in "${CASKS[@]}"; do
  echo "==> brew install --cask $c"
  brew install --cask "$c" || true
done

echo "All requested casks processed."
