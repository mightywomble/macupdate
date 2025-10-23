#!/bin/bash
set -e
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not installed. See https://brew.sh"
  exit 1
fi

echo "Updating Homebrew..."
brew update

prompt_yes_default() {
  # $1 = prompt
  local p="$1" ans
  read -r -p "$p" ans </dev/tty || ans=""
  if [ -z "$ans" ]; then
    return 0
  fi
  case "$ans" in
    [Yy]* ) return 0 ;;
  esac
  return 1
}

install_cask_with_replace() {
  local c="$1"
  [ -z "$c" ] && return 0
  echo "==> brew install --cask $c"
  set +e
  local out ec path base dest
  out=$(brew install --cask "$c" 2>&1)
  ec=$?
  set -e
  echo "$out"
  if [ $ec -eq 0 ]; then
    return 0
  fi
  if printf "%s" "$out" | grep -q "already an App at '"; then
    path=$(printf "%s" "$out" | sed -n "s/.*already an App at '\([^']\+\)'.*/\1/p" | head -n1)
    [ -z "$path" ] && path=$(printf "%s" "$out" | sed -n 's/.*already an App at "\([^"]\+\)".*/\1/p' | head -n1)
    if [ -n "$path" ] && [ -e "$path" ]; then
      if prompt_yes_default "Replace existing app at $path with Homebrew cask '$c'? [Y/n]: "; then
        if command -v osascript >/dev/null 2>&1; then
          osascript -e "tell application \"Finder\" to delete POSIX file \"$path\"" >/dev/null 2>&1 || true
        fi
        if [ -e "$path" ]; then
          base="$(basename \"$path\")"
          dest="$HOME/.Trash/${base%.*}-backup-$(date +%s).app"
          mv -f "$path" "$dest" 2>/dev/null || rm -rf "$path"
        fi
        echo "Retrying: brew install --cask $c"
        set +e
        brew install --cask "$c"
        ec=$?
        set -e
        return $ec
      fi
    fi
  fi
  # Fallback retry via reinstall
  set +e
  brew reinstall --cask "$c"
  ec=$?
  set -e
  return $ec
}

# Casks to install
CASKS=(
  "electric-sheep"
  "logi-options+"
  "maintenance"
  "onyx"
  "proxy-audio-device"
  "tailscale"
  "wireshark"
  "applite"
)

echo "Installing casks: ${CASKS[*]}"
for c in "${CASKS[@]}"; do
  install_cask_with_replace "$c" || true
done

echo "All requested casks processed."
