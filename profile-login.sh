#!/usr/bin/env bash
# Profile Login - isolated browser profiles for user-agent testing
# For educational and authorized testing purposes only.
set -Eeuo pipefail

APP_NAME="Profile Login"
BASE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/profile-login"
LOG_DIR="$BASE_DIR/logs"
FIREFOX_PROFILE="$BASE_DIR/firefox-profile"
CHROME_PROFILE="$BASE_DIR/chrome-profile"

# Test UA used by the Windows test launcher.
TEST_USER_AGENT='Mozilla/5.0 (Linux; Android 14; SM-S918W) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36'

cyan=$'\033[36m'
yellow=$'\033[33m'
red=$'\033[31m'
gray=$'\033[90m'
reset=$'\033[0m'

mkdir -p "$BASE_DIR" "$LOG_DIR"

pause_menu() {
  echo
  read -r -p "Press Enter to return to the menu..." _ || true
}

have_snap_app() {
  command -v snap >/dev/null 2>&1 && snap list "$1" >/dev/null 2>&1
}

have_flatpak_app() {
  command -v flatpak >/dev/null 2>&1 && flatpak info "$1" >/dev/null 2>&1
}

find_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

require_desktop() {
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "${red}Error: $APP_NAME requires a graphical Linux desktop session.${reset}" >&2
    exit 1
  fi
}

run_and_log() {
  local log_file="$1"
  shift
  local status=0
  "$@" >>"$log_file" 2>&1 || status=$?
  return "$status"
}

configure_firefox_test_profile() {
  local profile="$1"
  mkdir -p "$profile"
  # user.js is read by Firefox at every start and applies only to this profile.
  cat > "$profile/user.js" <<EOF
// Profile Login isolated test profile. Does not alter the user's default profile.
user_pref("general.useragent.override", "$TEST_USER_AGENT");
EOF
}

launch_firefox() {
  local browser="" mode="" profile="" resolved="" log="$LOG_DIR/firefox.log" status=0
  if browser="$(find_command firefox firefox-esr)"; then
    resolved="$(readlink -f "$browser" 2>/dev/null || printf '%s' "$browser")"
    mode="native"
    # Ubuntu may expose the Firefox Snap through /usr/bin/firefox.
    if [[ "$browser" == /snap/bin/* || "$resolved" == /snap/* ]] || { [[ "$browser" == /usr/bin/firefox ]] && have_snap_app firefox; }; then
      mode="snap"
    elif [[ "$browser" == *org.mozilla.firefox* || "$resolved" == *flatpak* ]]; then
      mode="flatpak"
    fi
  elif have_snap_app firefox; then
    mode="snap"
  elif have_flatpak_app org.mozilla.firefox; then
    mode="flatpak"
  else
    echo "${red}Firefox was not found.${reset}"
    echo "Install Firefox / Firefox ESR, the Firefox Snap, or the Firefox Flatpak."
    return 1
  fi

  # Snap and Flatpak are confined: keep their profiles inside their writable app data.
  case "$mode" in
    snap) profile="$HOME/snap/firefox/common/profile-login-profile" ;;
    flatpak) profile="$HOME/.var/app/org.mozilla.firefox/config/profile-login-profile" ;;
    *) profile="$FIREFOX_PROFILE" ;;
  esac
  configure_firefox_test_profile "$profile"
  echo "Using isolated Firefox test profile: $profile"
  echo "Configured profile User-Agent override for this test profile only."
  case "$mode" in
    snap)
      run_and_log "$log" snap run firefox --no-remote --new-instance --profile "$profile" || status=$?
      ;;
    flatpak)
      run_and_log "$log" flatpak run org.mozilla.firefox --no-remote --new-instance --profile "$profile" || status=$?
      ;;
    native)
      run_and_log "$log" "$browser" --no-remote --new-instance --profile "$profile" || status=$?
      ;;
  esac

  if (( status != 0 )); then
    echo "${red}Firefox exited with status $status.${reset}"
    echo "Log file: $log"
    echo "Close any Firefox window using this Profile Login profile and try again."
    return "$status"
  fi
  echo "Firefox closed normally."
}

launch_chrome() {
  local browser="" mode="" profile="" resolved="" log="$LOG_DIR/chrome.log" status=0
  if browser="$(find_command google-chrome google-chrome-stable)"; then
    resolved="$(readlink -f "$browser" 2>/dev/null || printf '%s' "$browser")"
    mode="native"
    if [[ "$browser" == /snap/bin/* || "$resolved" == /snap/* ]]; then
      mode="snap"
    fi
  elif browser="$(find_command chromium chromium-browser)"; then
    resolved="$(readlink -f "$browser" 2>/dev/null || printf '%s' "$browser")"
    mode="native"
    if [[ "$browser" == /snap/bin/* || "$resolved" == /snap/* ]] || { [[ "$browser" == /usr/bin/chromium-browser ]] && have_snap_app chromium; }; then
      mode="snap"
    elif [[ "$browser" == *org.chromium.Chromium* || "$resolved" == *flatpak* ]]; then
      mode="flatpak-chromium"
    fi
  elif have_snap_app chromium; then
    mode="snap"
  elif have_flatpak_app com.google.Chrome; then
    mode="flatpak-chrome"
  elif have_flatpak_app org.chromium.Chromium; then
    mode="flatpak-chromium"
  else
    echo "${red}Google Chrome / Chromium was not found.${reset}"
    echo "Install Google Chrome, Chromium, its Snap, or a supported Flatpak."
    return 1
  fi

  case "$mode" in
    snap) profile="$HOME/snap/chromium/common/profile-login-profile" ;;
    flatpak-chrome) profile="$HOME/.var/app/com.google.Chrome/config/profile-login-profile" ;;
    flatpak-chromium) profile="$HOME/.var/app/org.chromium.Chromium/config/profile-login-profile" ;;
    *) profile="$CHROME_PROFILE" ;;
  esac
  mkdir -p "$profile"
  echo "Using isolated Chrome / Chromium test profile: $profile"
  echo "Launching with the test User-Agent override..."
  case "$mode" in
    snap)
      run_and_log "$log" snap run chromium --user-data-dir="$profile" --user-agent="$TEST_USER_AGENT" --no-first-run || status=$?
      ;;
    flatpak-chrome)
      run_and_log "$log" flatpak run com.google.Chrome --user-data-dir="$profile" --user-agent="$TEST_USER_AGENT" --no-first-run || status=$?
      ;;
    flatpak-chromium)
      run_and_log "$log" flatpak run org.chromium.Chromium --user-data-dir="$profile" --user-agent="$TEST_USER_AGENT" --no-first-run || status=$?
      ;;
    native)
      run_and_log "$log" "$browser" --user-data-dir="$profile" --user-agent="$TEST_USER_AGENT" --no-first-run || status=$?
      ;;
  esac

  if (( status != 0 )); then
    echo "${red}Chrome / Chromium exited with status $status.${reset}"
    echo "Log file: $log"
    echo "Close any Chrome / Chromium window using this Profile Login profile and try again."
    return "$status"
  fi
  echo "Chrome / Chromium closed normally."
}

main() {
  require_desktop
  while true; do
    clear 2>/dev/null || true
    echo "${cyan}==============================================${reset}"
    echo "${cyan}                 PROFILE LOGIN${reset}"
    echo "${gray}     For educational and testing purposes only${reset}"
    echo "${cyan}==============================================${reset}"
    echo
    echo "1. Firefox"
    echo "2. Google Chrome"
    echo "3. Exit"
    echo
    local choice
    read -r -p "Select an option [1-3]: " choice || exit 0
    case "$choice" in
      1) launch_firefox || true; pause_menu ;;
      2) launch_chrome || true; pause_menu ;;
      3) echo "Goodbye."; exit 0 ;;
      *) echo "${yellow}Invalid choice. Please select 1, 2, or 3.${reset}"; sleep 1 ;;
    esac
  done
}

main "$@"
