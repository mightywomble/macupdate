#!/usr/bin/env bash
set -euo pipefail

# --- Colors and Icons ---
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color
ICON_OK="✅"
ICON_WARN="⚠️"
ICON_BAD="❌"

# --- Prerequisite Check ---
if ! command -v brew >/dev/null 2>&1; then
  echo -e "${RED}Error: Homebrew (brew) is not installed.${NC}"
  echo "Please install it from https://brew.sh/ and re-run."
  exit 1
fi

# --- Gather Installed Items ---
FORMULAE=$(brew list --formula 2>/dev/null || true)
CASKS=$(brew list --cask 2>/dev/null || true)
OUTDATED_FORMULAE=$(brew outdated --formula --quiet 2>/dev/null || true)
# --greedy includes casks that auto-update and would otherwise be skipped
OUTDATED_CASKS=$(brew outdated --cask --greedy --quiet 2>/dev/null || true)

is_outdated_formula() {
  local name="$1"
  printf "%s\n" "$OUTDATED_FORMULAE" | grep -qx -- "$name"
}

is_outdated_cask() {
  local name="$1"
  printf "%s\n" "$OUTDATED_CASKS" | grep -qx -- "$name"
}

is_expired() {
  # $1 = type (formula|cask), $2 = name
  local type="$1" name="$2" flag=""
  if [ "$type" = "cask" ]; then
    flag="--cask"
  fi
  # Look for signals of deprecation/disablement
  if brew info $flag "$name" 2>/dev/null | grep -qiE 'deprecated|disabled|deprecate!|disable!'; then
    return 0
  fi
  return 1
}

UPTODATE_COUNT=0
OUTDATED_COUNT=0
EXPIRED_COUNT=0

printf "Scanning installed Homebrew formulae...\n"
for f in $FORMULAE; do
  [ -z "$f" ] && continue
  if is_expired formula "$f"; then
    echo -e "${RED}${ICON_BAD} ${f} (deprecated/disabled)${NC}"
    EXPIRED_COUNT=$((EXPIRED_COUNT+1))
  elif is_outdated_formula "$f"; then
    echo -e "${YELLOW}${ICON_WARN} ${f} (update available)${NC}"
    OUTDATED_COUNT=$((OUTDATED_COUNT+1))
  else
    echo -e "${GREEN}${ICON_OK} ${f} (up-to-date)${NC}"
    UPTODATE_COUNT=$((UPTODATE_COUNT+1))
  fi
done

printf "\nScanning installed Homebrew casks...\n"
for c in $CASKS; do
  [ -z "$c" ] && continue
  if is_expired cask "$c"; then
    echo -e "${RED}${ICON_BAD} ${c} (deprecated/disabled)${NC}"
    EXPIRED_COUNT=$((EXPIRED_COUNT+1))
  elif is_outdated_cask "$c"; then
    echo -e "${YELLOW}${ICON_WARN} ${c} (update available)${NC}"
    OUTDATED_COUNT=$((OUTDATED_COUNT+1))
  else
    echo -e "${GREEN}${ICON_OK} ${c} (up-to-date)${NC}"
    UPTODATE_COUNT=$((UPTODATE_COUNT+1))
  fi
done

TOTAL=$((UPTODATE_COUNT+OUTDATED_COUNT+EXPIRED_COUNT))
echo ""
echo "Summary: ${TOTAL} total | ${UPTODATE_COUNT} up-to-date | ${OUTDATED_COUNT} need update | ${EXPIRED_COUNT} deprecated/disabled"

echo ""
# --- Prompt to generate Ansible playbook ---
ans=""
if [ -t 0 ]; then
  read -r -p "Do you want to generate an Ansible playbook to reinstall these apps? (Y/n) " ans
else
  # No TTY available; default to No to avoid unintended actions
  ans="n"
fi
if [[ -z "$ans" || "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  PLAYBOOK="brew_reinstall.yml"
  echo "Creating ${PLAYBOOK}..."

  # Serialize lists into YAML arrays
  echo "---" > "$PLAYBOOK"
  echo "- name: Reinstall Homebrew apps" >> "$PLAYBOOK"
  echo "  hosts: localhost" >> "$PLAYBOOK"
  echo "  connection: local" >> "$PLAYBOOK"
  echo "  gather_facts: false" >> "$PLAYBOOK"
  echo "  vars:" >> "$PLAYBOOK"
  echo "    formulae:" >> "$PLAYBOOK"
  for f in $FORMULAE; do
    [ -n "$f" ] && printf "      - %s\n" "$f" >> "$PLAYBOOK"
  done
  echo "    casks:" >> "$PLAYBOOK"
  for c in $CASKS; do
    [ -n "$c" ] && printf "      - %s\n" "$c" >> "$PLAYBOOK"
  done
  cat >> "$PLAYBOOK" <<'YAML'
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
      when: formulae | length > 0

    - name: Install Homebrew casks
      community.general.homebrew_cask:
        name: "{{ casks }}"
        state: present
      when: casks | length > 0
YAML

  echo "Playbook written to ${PLAYBOOK}"
fi
