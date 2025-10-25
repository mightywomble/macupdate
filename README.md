# macupdatecheck

A macOS utility that scans /Applications and ~/Applications, detects which apps are available as Homebrew casks, and interactively generates (and optionally runs) an installer script. It also consults the Homebrew Formulae API to suggest alternatives and can replace pre-existing, non-brew .app bundles when installing via Homebrew.

## 📦 Version history
- 1.2 — 2025-10-22
  - ➕ Added per‑app skip option for alternative (amber) suggestions in checker.sh, so you can bypass long candidate lists quickly.
  - 🆕 Added brewmelater.sh to scan all installed Homebrew formulae and casks, show status (up‑to‑date/needs update/deprecated), and optionally generate an Ansible playbook (brew_reinstall.yml) to reinstall them.
  - 🛠️ Prompt handling improvements (avoid unintended actions when no TTY).
- 1.0 — 2025-10-01
  - 🎉 Initial release of checker.sh with scanning, alternative suggestions, and installer generation.

## Features
- Fast scan of installed apps using Spotlight (mdfind)
- Classifies apps with icons:
  - ✅ Green: already installable/managed via Homebrew
  - 🤔 Amber: possible alternatives (suggested via brew search + online API)
  - ❌ Red: not available (or macOS core apps)
- Online lookup using the Homebrew Formulae API when local searches miss
- Interactive post-scan flow to choose alternatives and build an installer
- Per‑app skip for alternative suggestions (⏭️ quickly skip long lists)
- Generates ./brew_app_installer.sh and can run it immediately
- Installer auto-adds Applite for easy app management
- Handles “Error: It seems there is already an App at …” and prompts to replace the existing app cleanly

## Requirements
- macOS
- Homebrew (brew)
- curl (optional, enables online lookups and better alternatives)

## Quick start
```bash path=null start=null
chmod +x checker.sh
./checker.sh
```

## 🔍 Example scan output
```text path=null start=null
Scanning for apps in /Applications and ~/Applications...
This may take a moment while checking Homebrew...
-----------------------------------------------------
✅ Visual Studio Code
    -> Note: Available to install.
    -> Run: brew install --cask visual-studio-code
🤔 Warp
    -> Note: No exact match for 'warp'.
    -> Found similar casks: warp
✅ Warp
    -> Note: Found via online Homebrew lookup.
    -> Run: brew install --cask warp
    -> Ref: https://formulae.brew.sh/cask/warp
❌ Safari
    -> Note: Core macOS app, not managed by Homebrew.
-----------------------------------------------------
Scan complete.
Create a Homebrew install script from found apps? [y/N]: y
Reviewing alternatives for apps marked as 'maybe'...
- Warp:
  [1/1] Warp -> warp
    Install? [Y/n]:
Creating ./brew_app_installer.sh ...
Installer script created at: ./brew_app_installer.sh
Run the installer script now? [Y/n]:
```

## 🚀 Example installer output (brew_app_installer.sh)
```text path=null start=null
Updating Homebrew...
==> Auto-updated Homebrew!

Installing casks: visual-studio-code warp applite
==> brew install --cask visual-studio-code
==> Downloading ...
==> Installing Cask visual-studio-code
🍺  visual-studio-code was successfully installed!
==> brew install --cask warp
🍺  warp was successfully installed!
==> brew install --cask applite
🍺  applite was successfully installed!

All requested casks processed.
```

## What the generated installer does
- Installs all selected casks (greens + chosen alternatives)
- Always includes `applite` for GUI management of Homebrew apps
- For each cask, if Homebrew reports “already an App at '…'”, the script asks to replace the existing app and retries install

### Replace-existing-app flow
- Prompts: “Replace existing app at /Applications/Foo.app with Homebrew cask 'foo'? [Y/n]:” (Enter defaults to Yes)
- Attempts Finder delete (moves to Trash); falls back to moving to `~/.Trash` or removing the bundle
- Retries `brew install --cask foo`

## How to run only the installer later
```bash path=null start=null
./brew_app_installer.sh
```

## 🧰 Script structure (checker.sh)
- Colors and icons: visual indicators for results
- Prerequisite check: ensures brew is installed
- Installed casks cache: `brew list --cask` once for speed
- App discovery: uses `mdfind` to enumerate .app bundles in system and user Applications folders
- Name normalization (caskify): lowercases, replaces spaces with dashes, strips special chars
- Checks per app:
  1) Already managed by Homebrew (exact token match)
  2) Exact cask available (`brew info --cask <name>`) -> ✅
  3) Broad local search (`brew search --casks <App Name>`) -> 🤔 with candidates
  4) Online exact lookup (Homebrew API: `/api/cask/<name>.json`) -> ✅
  5) Online search alternatives (`/api/search.json?q=<App Name>`) -> 🤔 with candidates
  6) Otherwise -> ❌ (with filtering of macOS core apps)
- Post-scan interactive builder:
  - Prompts to create an installer
  - Iterates each amber app’s candidate list, asking per-candidate:
    - Shows progress as `[x/y] App -> candidate`
    - Default Yes on Enter
  - Produces `./brew_app_installer.sh` and offers to run it immediately
- Installer helpers (embedded in the generated script):
  - `prompt_yes_default`: default-Yes prompt reader using `/dev/tty`
  - `install_cask_with_replace`: wraps `brew install --cask`, detects “already an App at …”, prompts, removes old app, and retries
- Cleanup: temporary files removed via `trap`

## 🧪 brewmelater.sh

brewmelater.sh scans all installed Homebrew items and helps you rebuild your environment via Ansible.

- ✅ Marks up‑to‑date items
- ⚠️ Highlights items needing updates (including greedy casks)
- ❌ Flags deprecated/disabled items via brew info metadata
- ✍️ Optionally generates brew_reinstall.yml that:
  - Installs Homebrew (if missing)
  - Reinstalls all detected formulae and casks using community.general.homebrew and homebrew_cask

Run:
```bash path=null start=null
./brewmelater.sh
# Answer Y to generate brew_reinstall.yml
```

Example run of the generated playbook (brew_reinstall.yml):
```text path=null start=null
PLAY [Reinstall Homebrew apps] *************************************************

TASK [Ensure Homebrew is installed] ********************************************
ok: [localhost]

TASK [Install Homebrew formulae] ***********************************************
changed: [localhost]

TASK [Install Homebrew casks] **************************************************
changed: [localhost]

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=2    unreachable=0    failed=0
```

Generated playbook (snippet):
```yaml path=null start=null
---
- name: Reinstall Homebrew apps
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    formulae:
      - git
      - wget
    casks:
      - iterm2
      - visual-studio-code
  tasks:
    - name: Ensure Homebrew is installed
      shell: |
        if ! command -v brew >/dev/null; then
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
      args:
        executable: /bin/bash
      environment:
        NONINTERACTIVE: "1"

    - name: Install Homebrew formulae
      community.general.homebrew:
        name: "{{ formulae }}"
        state: present
        update_homebrew: true

    - name: Install Homebrew casks
      community.general.homebrew_cask:
        name: "{{ casks }}"
        state: present
```

## Troubleshooting
- brew not found: install Homebrew from https://brew.sh and re-run
- No prompts for alternatives: ensure you answered `y` when asked to create the installer; the script reads prompts from `/dev/tty`
- Network issues: online lookups require `curl` and internet access

## Notes
- The script uses `mdfind` for speed; Spotlight indexing should be enabled
- Online API used: https://formulae.brew.sh/api


# Keeping track of Brew Updates


This is a simple script for [SwiftBar](https://swiftbar.app/) that adds a Homebrew update notifier to your macOS menu bar.

It silently checks for outdated Homebrew packages in the background and displays a small icon with the number of available updates. It provides a simple, clickable menu to update individual packages, dismiss updates, or upgrade all packages at once.

Instead of manually running `brew outdated` every day, this gives you a passive, at-a-glance reminder and brings a convenient GUI-like experience to your command-line package manager.

## Features

-   ✅ **Auto-detects Homebrew:** Works out-of-the-box on both Apple Silicon (e.g., M1/M2/M3) and Intel-based Macs.
    
-   🖥️ **Native Look & Feel:** Sits in your menu bar and uses Apple's SF Symbols for a clean, system-integrated icon (`:arrow.down.circle:` or `:checkmark.circle:`).
    
-   🔔 **Update Counter:** Displays a badge with the number of available updates (e.g., `(3)`).
    
-   📋 **Detailed List:** Clicking the icon shows a dropdown list of all packages needing an update, complete with their `from -> to` version numbers.
    
-   🖱️ **One-Click Actions:**
    
    -   **Update:** Update a single package by clicking "Update". A Terminal window will pop up to show the process.
        
    -   **Dismiss:** Ignore a specific update (e.g., a buggy version) until the _next_ version is released.
        
    -   **Upgrade All:** A convenient button to run `brew upgrade` for all packages.
        
-   ⚙️ **Configurable Schedule:** Runs every hour by default. You can change this by renaming the file (e.g., `brew_updates.30m.sh` for 30 minutes).
    
-   🧹 **Utility Functions:** Includes "Refresh Menu" and "Clear Dismissed List" for easy management.
    

## Installation

This script requires [SwiftBar](https://swiftbar.app/) and [jq](https://stedolan.github.io/jq/) (a command-line JSON processor).

### Step 1: Install Tools

Open your Terminal and use Homebrew to install `swiftbar` and `jq`:

Bash

```
brew install swiftbar jq

```

### Step 2: Set Up SwiftBar Plugin Folder

1.  Launch **SwiftBar** from your Applications folder.
    
2.  On first launch, it will ask you to choose a "Plugin Folder." We recommend creating a dedicated folder, such as `~/Documents/SwiftBar` or `~/Tools/SwiftBar`.
    
3.  If you already use SwiftBar, you can find your folder location by clicking the SwiftBar icon and going to **Preferences... > Plugin Folder**.
    

### Step 3: Create the Script File

1.  Navigate to the Plugin Folder you just set up.
    
2.  Create a new file named `brew_updates.1h.sh`.
    
    -   The `.1h` tells SwiftBar to run this script **every 1 hour**. You can change this to `10m` (10 minutes), `6h` (6 hours), etc.
        
3.  Copy the complete script from "The Script" section below and paste it into this new file.
    

### Step 4: Make the Script Executable

This is a crucial step. The script will not run unless it has permission to.

Open your Terminal and run the `chmod +x` command on your new script file. For example, if you used the `~/Documents/SwiftBar` folder:

Bash

```
chmod +x ~/Documents/SwiftBar/brew_updates.1h.sh

```

### Step 5: Refresh

The script should appear in your menu bar automatically. If not, click the main SwiftBar icon and select **Preferences > Refresh All**.

## The Script

Save the following code as `brew_updates.1h.sh` in your plugin folder.

Bash

```
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
    # | shell=... runs a command when clicked.
    # terminal=true opens a new Terminal window for it.
    # refresh=true tells SwiftBar to re-run this script when the command finishes.
    MENU_ITEMS+="--Update | shell='${BREW_PATH}' param1=upgrade param2=${NAME} terminal=true refresh=true\n"
    
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
echo "--Run in Terminal | shell='${BREW_PATH}' param1=upgrade terminal=true refresh=true"
echo "Refresh Menu | refresh=true"
echo "Clear Dismissed List | shell=/bin/rm param1=${DISMISSED_FILE} terminal=false refresh=true"

```

## Code Breakdown

Here’s what each section of the script does:

1.  **Configuration (`BREW_PATH`)** The script starts by checking for the `brew` executable in the two most common locations: `/opt/homebrew/bin` (for Apple Silicon Macs) and `/usr/local/bin` (for Intel Macs). It stores the correct path in a `$BREW_PATH` variable. If it can't find `brew`, it shows an error icon and stops.
    
2.  **Global Variables**
    
    -   `$SELF_PATH`: SwiftBar provides this variable. It's the full path to this script, which we need so the "Dismiss" action can call itself.
        
    -   `$DISMISSED_FILE`: This defines a simple text file, `.brew_updates_dismissed.txt`, in your home directory. This file will store a list of all updates you've chosen to ignore.
        
3.  **Action Handling (for "Dismiss")** This block (`if [ "$1" == "dismiss" ]...`) checks if the script was run with the first argument "dismiss". When you click the "Dismiss" sub-menu item, the script is re-run with `dismiss`, the app name, and the "to" version as arguments. This code catches those arguments, appends a line like `AppName@VersionTo` into the `$DISMISSED_FILE`, and then exits.
    
4.  **Main Menu Logic (JSON Parsing)** This is the main part of the script that runs on its hourly schedule.
    
    -   It runs `${BREW_PATH} outdated --json=v2` to get a detailed, machine-readable list of all outdated packages.
        
    -   It pipes this JSON output to `jq`, which extracts and flattens the list of formulas and casks into a single, easy-to-loop format.
        
5.  **The Main Loop (`while read -r item...`)** The script loops through each line of output from `jq`.
    
    -   It parses the `name`, `V_FROM` (installed version), and `V_TO` (available version).
        
    -   It includes a **sanity check** (`if [ -z "$NAME" ]...`) to skip any "phantom" updates that `brew` might report (where the name is blank).
        
    -   It creates a unique `DISMISS_KEY` (e.g., `htop@3.3.0`).
        
    -   It uses `grep` to check if that _exact_ key exists in the `$DISMISSED_FILE`.
        
    -   If the key is **not** found, it increments the `$COUNT` and builds the menu strings for that app, including the `AppName v1.0 → v1.1` title line and its "Update" and "Dismiss" sub-menu items.
        
6.  **Printing the Menu (The `echo` commands)** This is what generates the menu you see.
    
    -   **Menu Bar Icon**: The _very first line_ `echo`-ed is what appears in the menu bar. We use `if [ "$COUNT" -gt 0 ]...` to show the update icon `(:arrow.down.circle:)` and count, or the checkmark icon `(:checkmark.circle:)` if the count is zero. The `| symbolize=true templateImage=true` parameters tell SwiftBar to convert the text name into a real SF Symbol icon and color it to match your menu bar.
        
    -   **Separator**: `echo "---"` creates the horizontal divider line.
        
    -   **Dynamic List**: `echo -e "$MENU_ITEMS"` prints the entire list of updates we built in the loop.
        
    -   **Static Items**: The final `echo` commands print the utility items at the bottom of the list ("Upgrade All Packages", "Refresh Menu", etc.).
        

## Troubleshooting

-   **Problem:** The icon in my menu bar is three dots (`...`) or an error (`⚠️`).
    
    -   **Solution 1:** You may not have `jq` installed. Run `brew install jq` in your Terminal.
        
    -   **Solution 2:** The script is not executable. Run `chmod +x /path/to/your/brew_updates.1h.sh` (see Step 4).
        
    -   **Solution 3:** `brew` is not in one of the auto-detected paths. Run `which brew` in your Terminal, copy the path, and manually replace the `BREW_PATH="..."` logic at the top of the script with your path, like: `BREW_PATH="/your/custom/path/bin/brew"`.
        
-   **Problem:** I see a blank `->` item in the list.
    
    -   **Solution:** You are running an older version of this script. Copy the latest version from this README, which includes a sanity check to filter out these "phantom" updates. After saving, click "Refresh Menu".
        
-   **Problem:** My script won't refresh, or my script changes aren't showing up.
    
    -   **Solution:** SwiftBar only runs the script based on the time in its filename (e.g., `.1h`). To force an update, either click the "Refresh Menu" item inside the script's own dropdown, or click the main SwiftBar icon and go to **Preferences > Refresh All**.




## Contributing
Issues and PRs welcome. Please keep changes POSIX-sh compatible and prefer single-pass lookups for performance.

## License
MIT


## SwiftBar: Disk Usage (disk-usage.1h.py)

A SwiftBar plugin that lists all mounted disks and shows a compact, macOS‑like view of their usage.

### What it does
- Shows each mounted disk on its own line with a proportional usage bar.
- Uses SF Symbols in the menubar and dropdown for a native look.
- Displays: volume name, bar, used %, free (GB), and total (GB).
- Provides actions per volume: Open, Reveal in Finder, and Eject.
- Updates every hour (via the .1h filename suffix).

### Features
- Aligned, monospace columns for readability.
- Color status by usage: green (<70%), orange (70–89%), red (90%+).
- Finder integration (open/reveal) and diskutil unmount from the menu.
- Overall usage shown in the menubar title.

### Installation
Requirements: SwiftBar and Python 3.

1) Copy or symlink the plugin into your SwiftBar plugin folder.
```bash path=null start=null
ln -s "$(pwd)/disk-usage.1h.py" "$HOME/Library/Application Support/SwiftBar/Plugins/"
```
2) Ensure it’s executable (already set in repo):
```bash path=null start=null
chmod +x disk-usage.1h.py
```
3) Refresh SwiftBar (Preferences → Refresh All) if it doesn’t appear.

To change the refresh interval, rename the file (e.g., `disk-usage.30m.py` for every 30 minutes).

### How to update it
- Pull the latest changes into this repository and SwiftBar will pick up updates on the next refresh.
- Or edit `disk-usage.1h.py` locally; changes appear after Refresh All.

### Customization
You can tweak visuals inside `disk-usage.1h.py`:
- FONT, FONT_SIZE, BAR_WIDTH
- Thresholds for color (search for status_color)
- Column widths and truncation of volume names
