#!/bin/bash

# ---
# Brew Cask Scanner
# Scans /Applications and ~/Applications to see which apps are available on Homebrew.
# ---

# --- Colors and Icons ---
GREEN="\033[0;32m"
RED="\033[0;31m"
AMBER="\033[0;33m"
NC="\033[0m" # No Color

ICON_YES="✅"
ICON_NO="❌"
ICON_MAYBE="🤔"

# --- Temp data stores for post-scan install script generation ---
TMP_AVAILABLE=$(mktemp)
TMP_YELLOW=$(mktemp)
TMP_MANAGED=$(mktemp)
trap 'rm -f "$TMP_AVAILABLE" "$TMP_YELLOW" "$TMP_MANAGED"' EXIT

# --- Lightweight online helper (uses Homebrew Formulae API) ---
# If local brew checks fail, we try an online lookup for a cask using curl.
HAS_CURL=0
if command -v curl >/dev/null 2>&1; then
  HAS_CURL=1
fi

check_online_cask() {
  # $1 = cask name (e.g., warp)
  local name="$1"
  if [ "$HAS_CURL" -ne 1 ] || [ -z "$name" ]; then
    return 1
  fi
  # Use the official API: https://formulae.brew.sh/api/cask/<name>.json
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" "https://formulae.brew.sh/api/cask/${name}.json")
  if [ "$status" = "200" ]; then
    return 0
  fi
  return 1
}

search_online_cask_alternatives() {
  # $1 = free-form query (e.g., original app name)
  local query="$1"
  if [ "$HAS_CURL" -ne 1 ] || [ -z "$query" ]; then
    return 1
  fi
  # Use Homebrew search API and extract candidate cask tokens
  local resp tokens_all out token
  resp=$(curl -sG --data-urlencode "q=${query}" "https://formulae.brew.sh/api/search.json") || return 1
  # Extract all tokens in response
  tokens_all=$(printf "%s" "$resp" | grep -o '"token":"[^"]*"' | sed 's/.*"token":"\([^"]*\)"/\1/' | sort -u)
  out=""
  for token in $tokens_all; do
    if check_online_cask "$token"; then
      out+=" $token"
    fi
  done
  out=${out# } # trim leading space
  if [ -n "$out" ]; then
    echo "$out"
    return 0
  fi
  return 1
}

# --- Prerequisite Check ---
if ! command -v brew &> /dev/null; then
    echo -e "${RED}Error: Homebrew (brew) is not installed.${NC}"
    echo "Please install it from https://brew.sh/ to run this script."
    exit 1
fi

echo "Scanning for apps in /Applications and ~/Applications..."
echo "This may take a moment while checking Homebrew..."
echo "-----------------------------------------------------"

# --- Get list of already installed casks ---
# Running this once is much faster than checking inside the loop.
echo "Fetching installed cask list..."
INSTALLED_CASKS=$(brew list --cask)
echo "" # newline

# --- Find all apps ---
# Use mdfind (Spotlight) to get all .app bundles in the two main app folders.
# This is much faster and more reliable than 'find'.
APP_PATHS=$(mdfind 'kMDItemKind == "Application"' -onlyin /Applications -onlyin ~/Applications)

# Get a unique, sorted list of app names (not paths)
UNIQUE_APP_NAMES=$(while IFS= read -r app_path; do
    basename "$app_path" .app
done <<< "$APP_PATHS" | sort -u)

# --- Loop through each unique app name ---
while IFS= read -r app_name; do
    # Skip empty names
    if [ -z "$app_name" ]; then
        continue
    fi

    # Create the most likely cask name
    # e.g., "Visual Studio Code" -> "visual-studio-code"
    # e.g., "1Password 7" -> "1password-7"
    # It converts to lowercase, replaces spaces with hyphens, and removes most special chars.
    cask_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
    
    # Handle empty cask names if the app name was just symbols
    if [ -z "$cask_name" ]; then
        echo -e "${RED}${ICON_NO} ${app_name}${NC}"
        echo "    -> Note: Invalid app name for Homebrew search."
        continue
    fi

    # --- Check 1: Is it already installed by Homebrew? ---
    if echo "$INSTALLED_CASKS" | grep -q "^${cask_name}$"; then
        echo -e "${GREEN}${ICON_YES} ${app_name}${NC}"
        echo "    -> Note: Already managed by Homebrew."
        echo "$cask_name" >> "$TMP_MANAGED"
        continue
    fi

    # --- Check 2: Is an exact cask name available? ---
    # We use `brew info` as it's a direct lookup and faster than `brew search`.
    if brew info --cask "$cask_name" &> /dev/null; then
        echo -e "${GREEN}${ICON_YES} ${app_name}${NC}"
        echo "    -> Note: Available to install."
        echo "    -> Run: brew install --cask ${cask_name}"
        echo "$cask_name" >> "$TMP_AVAILABLE"
        continue
    fi
    
    # --- Check 3: No exact match. Let's do a broad search. ---
    # This is the slowest step, so it's last.
    # We search for the original app name, as our 'caskified' name failed.
    # We filter out 'Formulae' results.
    search_results=$(brew search --casks "$app_name" 2>/dev/null | grep -v 'Formulae')

    if [ -n "$search_results" ]; then
        # We found *something*
        echo -e "${AMBER}${ICON_MAYBE} ${app_name}${NC}"
        echo "    -> Note: No exact match for '${cask_name}'."
        # Clean up the search results for display
        results_cleaned=$(echo "$search_results" | awk '{print $1}' | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
        echo "    -> Found similar casks: ${results_cleaned}"
        # Store for later interactive selection (only if non-empty)
        if [ -n "$results_cleaned" ]; then
            echo "${app_name}|${results_cleaned}" >> "$TMP_YELLOW"
        fi
    else
        # --- Check 4: Try lightweight online lookup (Formulae API) ---
        if check_online_cask "$cask_name"; then
            echo -e "${GREEN}${ICON_YES} ${app_name}${NC}"
            echo "    -> Note: Found via online Homebrew lookup."
            echo "    -> Run: brew install --cask ${cask_name}"
            echo "    -> Ref: https://formulae.brew.sh/cask/${cask_name}"
            echo "$cask_name" >> "$TMP_AVAILABLE"
        else
            # --- Try online alternative search via API ---
            online_alts=$(search_online_cask_alternatives "$app_name" 2>/dev/null || true)
            if [ -n "$online_alts" ]; then
                echo -e "${AMBER}${ICON_MAYBE} ${app_name}${NC}"
                echo "    -> Note: Found possible casks via online search."
                echo "    -> Candidates: ${online_alts}"
                echo "${app_name}|${online_alts}" >> "$TMP_YELLOW"
            else
                # --- Check 5: Nothing found. ---
                # Filter out common core apps that will never be in Homebrew.
                case "$app_name" in
                    "Safari" | "Mail" | "Music" | "Messages" | "System Settings" | "Finder" | "Photos" | "Contacts" | "Calendar" | "Notes" | "Reminders" | "App Store" | "Freeform" | "Maps" | "News" | "Siri" | "Stocks" | "TV" | "Podcasts" | "VoiceMemos" | "Weather" | "Utilities" | "System Information" | "TextEdit" | "Stickies" | "QuickTime Player")
                        echo -e "${RED}${ICON_NO} ${app_name}${NC}"
                        echo "    -> Note: Core macOS app, not managed by Homebrew."
                        ;;
                    *)
                        # Truly not found.
                        echo -e "${RED}${ICON_NO} ${app_name}${NC}"
                        echo "    -> Note: Not found in Homebrew Cask repositories."
                        ;;
                esac
            fi
        fi
    fi
    
done <<< "$UNIQUE_APP_NAMES"

echo "-----------------------------------------------------"
echo "Scan complete."

# --- Post-scan: Offer to create installer script ---
read -r -p "Create a Homebrew install script from found apps? [y/N]: " MAKE_SCRIPT
if [[ "$MAKE_SCRIPT" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Allow user to pick alternatives for yellow entries
    if [ -s "$TMP_YELLOW" ]; then
        echo "Reviewing alternatives for apps marked as 'maybe'..."
        while IFS= read -r line; do
            app_name_prompt="${line%%|*}"
            choices_line_raw="${line#*|}"
            # Sanitize and normalize choices line
            choices_line=$(printf "%s" "$choices_line_raw" | tr '\r,' '  ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ *//' -e 's/ *$//')
            # Skip if no choices parsed
            if [ -z "$choices_line" ] || [ "$choices_line" = "$line" ]; then
                continue
            fi

            # Build a tokens array (space-separated tokens), normalizing common formats
            tokens=()
            for raw in $choices_line; do
                cand="$raw"
                # drop headers or noise
                case "$cand" in
                  "==>"|"Casks"|"Formulae"|"Candidates:") continue ;;
                esac
                # strip tap prefixes and common noise
                cand=${cand#homebrew/cask/}
                cand=${cand#homebrew/core/}
                cand=${cand%,}
                # accept broad token charset
                if [ -n "$cand" ]; then
                  # de-duplicate
                  if [[ " ${tokens[*]} " != *" $cand "* ]]; then
                    tokens+=("$cand")
                  fi
                fi
            done

            total=${#tokens[@]}
            if [ "$total" -eq 0 ]; then
                echo "- $app_name_prompt: (no candidates parsed)"
                continue
            fi
            echo "- $app_name_prompt:"

            i=1
            for cand in "${tokens[@]}"; do
                echo "  [$i/$total] $app_name_prompt -> $cand"
                read -r -p "    Install? [Y/n]: " yn </dev/tty
                if [[ -z "$yn" || "$yn" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    echo "$cand" >> "$TMP_AVAILABLE"
                fi
                i=$((i+1))
            done
        done < "$TMP_YELLOW"
    fi

    # Build unique list of casks to install (greens + chosen yellows)
    INSTALL_LIST=$(sort -u "$TMP_AVAILABLE")

    # Create installer script
    INSTALL_SCRIPT="./brew_app_installer.sh"
    echo "Creating $INSTALL_SCRIPT ..."

    # Header
    cat > "$INSTALL_SCRIPT" <<'SCRIPT_HEAD'
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
SCRIPT_HEAD

    # Add casks
    if [ -n "$INSTALL_LIST" ]; then
        while IFS= read -r c; do
            [ -n "$c" ] && echo "  \"$c\"" >> "$INSTALL_SCRIPT"
        done <<< "$INSTALL_LIST"
    fi

    # Always include Applite for managing apps
    echo "  \"applite\"" >> "$INSTALL_SCRIPT"

    # Footer + install loop
    cat >> "$INSTALL_SCRIPT" <<'SCRIPT_TAIL'
)

echo "Installing casks: ${CASKS[*]}"
for c in "${CASKS[@]}"; do
  install_cask_with_replace "$c" || true
done

echo "All requested casks processed."
SCRIPT_TAIL

    chmod +x "$INSTALL_SCRIPT"
    echo "Installer script created at: $INSTALL_SCRIPT"

    # Run the installer script now
    read -r -p "Run the installer script now? [Y/n]: " RUN_NOW
    if [[ -z "$RUN_NOW" || "$RUN_NOW" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        "$INSTALL_SCRIPT"
    else
        echo "You can run it later with: $INSTALL_SCRIPT"
    fi
fi
