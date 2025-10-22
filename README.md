# macupdatecheck

A macOS utility that scans /Applications and ~/Applications, detects which apps are available as Homebrew casks, and interactively generates (and optionally runs) an installer script. It also consults the Homebrew Formulae API to suggest alternatives and can replace pre-existing, non-brew .app bundles when installing via Homebrew.

## Features
- Fast scan of installed apps using Spotlight (mdfind)
- Classifies apps with icons:
  - ✅ Green: already installable/managed via Homebrew
  - 🤔 Amber: possible alternatives (suggested via brew search + online API)
  - ❌ Red: not available (or macOS core apps)
- Online lookup using the Homebrew Formulae API when local searches miss
- Interactive post-scan flow to choose alternatives and build an installer
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

## Example scan output
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

## Script structure (checker.sh)
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

## Troubleshooting
- brew not found: install Homebrew from https://brew.sh and re-run
- No prompts for alternatives: ensure you answered `y` when asked to create the installer; the script reads prompts from `/dev/tty`
- Network issues: online lookups require `curl` and internet access

## Notes
- The script uses `mdfind` for speed; Spotlight indexing should be enabled
- Online API used: https://formulae.brew.sh/api

## Contributing
Issues and PRs welcome. Please keep changes POSIX-sh compatible and prefer single-pass lookups for performance.

## License
MIT
