# Profile Login for Linux

A lightweight browser launcher for graphical Linux desktops. Choose Firefox or Chrome/Chromium and open a **separate, standard browser profile** without changing your normal browsing data.

> This tool does not impersonate Android or managed devices, alter authentication signals, or bypass IT device-access policies. Corporate access depends on your organization's identity, device-compliance, and security requirements.

## Requirements

- Linux with a graphical desktop (X11 or Wayland)
- Bash
- Firefox/Firefox ESR or Google Chrome/Chromium
- `curl` for the one-line command

No `sudo` or root privileges required.

## Run directly from GitHub

Review the [script](profile-login.sh) before running:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/themehdi/profile-poc/main/profile-login.sh)"
```

This runs the current script directly; it does not install it. The selected browser stays attached to the terminal while running, so launch errors are visible. Close the browser to return to the shell.

## Download, review, and run

```bash
curl -fL -o profile-login.sh https://raw.githubusercontent.com/themehdi/profile-poc/main/profile-login.sh
less profile-login.sh
chmod +x profile-login.sh
./profile-login.sh
```

Alternatively, clone this repository:

```bash
git clone https://github.com/themehdi/profile-poc.git
cd profile-poc
bash profile-login.sh
```

## Menu

```text
=== Profile Login (Linux) ===
1. Firefox
2. Chrome / Chromium
3. Exit
```

## Isolated browser profiles

- Firefox (regular install): `~/.config/profile-login/firefox-profile`
- Firefox (Ubuntu Snap): `~/snap/firefox/common/profile-login-profile`
- Chrome/Chromium (regular install): `~/.config/profile-login/chrome-profile`
- Chromium (Snap): `~/snap/chromium/common/profile-login-profile`
- If `XDG_CONFIG_HOME` is set, the script uses that directory instead of `~/.config`.
- Existing default browser profiles are not modified.
- Isolated profiles can still store cookies, history, and other browser data.

Close the dedicated browser before reopening the same profile.

To remove the regular-install profiles after closing the browsers:

```bash
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/profile-login"
```

For Snap-installed browsers, remove their dedicated `profile-login-profile` directories under `~/snap/firefox/common/` or `~/snap/chromium/common/` only after closing them. Do not delete the entire `~/snap` directory.

## Troubleshooting

- **Firefox already running:** close the separate Firefox instance, wait for it to exit, and retry. The script uses a dedicated Snap-accessible profile on Ubuntu when Firefox is installed as a Snap. Never delete lock files while Firefox is running.
- **Launcher diagnostics:** Firefox startup output is shown in the terminal and saved to `launcher.log` inside its dedicated profile directory. The launcher creates the profile on first run and reuses it on subsequent launches.
- **Browser not found:** install a supported browser with your distribution's package manager.
- **Graphical session required:** run from a Linux desktop, not a headless terminal.
- **Corporate login denied:** follow your organization's approved device enrollment and sign-in policies.
- **Security:** a one-line download-and-run executes the current script on `main`. Inspect first or pin to a reviewed commit.

## Scope

This project is a convenience launcher for standard browser profile isolation, not an official authentication client or a way around security controls.


## Full platform-signal inspector (local-only)

The additional [profile-login-full.sh](profile-login-full.sh) script opens Firefox or Chrome/Chromium using a dedicated browser profile and displays a local diagnostic page for **five browser/device-platform signals**:

| Signal | What it shows |
|---|---|
| HTTP `User-Agent` | Browser identity and claimed OS in request headers |
| `navigator.userAgent` | JavaScript-visible User-Agent |
| `navigator.platform` | JavaScript-visible platform |
| `navigator.userAgentData` | User-Agent Client Hints, where supported |
| `Sec-CH-UA-Platform` | Platform Client Hint in requests, where supported |

Run it directly:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/themehdi/profile-poc/main/profile-login-full.sh)"
```

Or download and inspect it first:

```bash
curl -fL -o profile-login-full.sh https://raw.githubusercontent.com/themehdi/profile-poc/main/profile-login-full.sh
less profile-login-full.sh
bash profile-login-full.sh
```

**Privacy and scope:** The diagnostic page runs on `127.0.0.1` with a randomly assigned local port and does not send its results to external servers. It does **not** change platform signals or claim managed-device identity. Missing Client Hints are reported as unsupported/not sent, not fabricated. The local test server stops when the script exits; close the browser window to return to the shell.
