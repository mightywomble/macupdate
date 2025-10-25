#!/bin/bash

# --- Configuration ---
# Auto-detect the brew path
if [ -f "/opt/homebrew/bin/brew" ]; then
  BREW_PATH="/opt/homebrew/bin/brew" # Apple Silicon path
elif [ -f "/usr/local/bin/brew" ]; then
  BREW_PATH="/usr/local/bin/brew" # Intel path
else
  # If brew is not found, show an error in the menu bar and exit
  echo ":exclamationmark.triangle: | symbolize=true templateImage=true"
  echo "---"
  echo "Homebrew executable not found."
  echo "Searched in /opt/homebrew/bin and /usr/local/bin"
  exit 1
fi
# --- End Configuration ---


# This is the path to the script itself, provided by SwiftBar
# We use it so the "Dismiss" action can call this same script.
SELF_PATH="${SWIFTBAR_PLUGIN_PATH}"

# File to store dismissed updates.
# We'll store "AppName@VersionTo" strings here.
DISMISSED_FILE="$HOME/.brew_updates_dismissed.txt"
touch "$DISMISSED_FILE" # Ensure the file exists

# --- Handle Actions ---
# This part runs *only* if the script is called with "dismiss"
# as the first argument (i.e., you clicked "Dismiss").
if [ "$1" == "dismiss" ]; then
  APP_NAME=$2
  VERSION_TO=$3
  
  # Add the specific "App@Version" to the dismissed file
  echo "${APP_NAME}@${VERSION_TO}" >> "$DISMISSED_FILE"
  
  # Exit successfully. We don't need to render a menu.
  exit 0
fi

# --- Main Menu Logic ---
# This part runs on the hourly schedule.

# Get all outdated info in one JSON blob from brew.
# We use '|| true' to prevent the script from failing (and showing an error)
# if brew itself has a temporary error.
#
# *** MODIFIED: Using $BREW_PATH variable ***
JSON_OUTPUT=$("${BREW_PATH}" outdated --json=v2 || true)

# If JSON is empty (e.g., brew error), show an error icon and exit
if [ -z "$JSON_OUTPUT" ]; then
  echo ":exclamationmark.triangle: | symbolize=true templateImage=true"
  echo "---"
  echo "Error: Could not run 'brew outdated'"
  exit 0
fi

# Use 'jq' to combine formulae and casks into a single,
# easy-to-loop stream of JSON objects.
ITEMS=$(echo "$JSON_OUTPUT" | jq -c '.formulae[] , .casks[]')

COUNT=0
MENU_ITEMS="" # We'll build the list of menu items here

# Loop through each outdated item
while read -r item; do
  # Parse the details for this item
  NAME=$(echo "$item" | jq -r '.name')
  V_FROM=$(echo "$item" | jq -r '.installed_versions[0]')
  V_TO=$(echo "$item" | jq -r '.current_version')

  # Sanity check: If brew returns a phantom item with no name, skip it.
  if [ -z "$NAME" ]; then
    continue
  fi

  # Create a unique key for this specific update (e.g., "htop@3.3.0")
  DISMISS_KEY="${NAME}@${V_TO}"

  # Check if this *exact* update is in our dismissed file.
  # -F: Treat as fixed string
  # -x: Match the whole line
  if ! grep -q -F -x "$DISMISS_KEY" "$DISMISSED_FILE"; then
    # --- This update is NOT dismissed ---
    
    # 1. Increment the counter
    COUNT=$((COUNT + 1))
    
    # 2. Add the main line for this app to our menu string
    # The \n is a newline character.
    MENU_ITEMS+="${NAME} ${V_FROM} → ${V_TO}\n"
    
    # 3. Add the "Update" sub-menu item
    # Open Terminal, run the update, then auto-close the Terminal window when done.
    MENU_ITEMS+="--Update | shell=/bin/bash param1=-lc param2=\"\\\"${BREW_PATH}\\\" upgrade ${NAME}; /usr/bin/osascript -e 'tell application \\\"Terminal\\\" to if (count of windows) > 0 then close front window'\" terminal=true refresh=true\n"
    
    # 4. Add the "Dismiss" sub-menu item
    # This calls this *same script* ($SELF_PATH) with args:
    # "dismiss", the app name, and the version to ignore.
    MENU_ITEMS+="--Dismiss | shell='${SELF_PATH}' param1=dismiss param2=${NAME} param3=${V_TO} refresh=true\n"
  fi
done <<< "$ITEMS" # This syntax feeds the $ITEMS variable into the 'while' loop


# --- Print the Final Menu to SwiftBar ---

# 1. The main menu bar item
# The very first line of output is what shows in the menu bar.
if [ "$COUNT" -gt 0 ]; then
  # Show the icon and the count.
  # :arrow.down.circle: is the inline name for the SF Symbol.
  # | symbolize=true tells SwiftBar to convert the :name: into an icon.
  # | templateImage=true is the correct parameter to make the icon match the menu bar color.
  echo ":arrow.down.circle: ($COUNT) | symbolize=true templateImage=true"
else
  # Just show the checkmark icon
  echo ":checkmark.circle: | symbolize=true templateImage=true"
fi

# 2. A separator line
echo "---"

# 3. The dynamic list of apps
if [ "$COUNT" -gt 0 ]; then
  echo -e "$MENU_ITEMS" # The '-e' interprets the \n newlines
else
  echo "All packages are up-to-date. ✅"
fi

# 4. Static utility items at the bottom
echo "---"
echo "Upgrade All Packages"
#
# *** MODIFIED: Using $BREW_PATH variable ***
echo "--Run in Terminal | shell=/bin/bash param1=-lc param2=\"\\\"${BREW_PATH}\\\" upgrade; /usr/bin/osascript -e 'tell application \\\"Terminal\\\" to if (count of windows) > 0 then close front window'\" terminal=true refresh=true"
echo "Refresh Menu | refresh=true"
echo "Clear Dismissed List | shell=/bin/rm param1=${DISMISSED_FILE} terminal=false refresh=true"
