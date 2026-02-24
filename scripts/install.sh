#!/usr/bin/env bash
# install.sh: Sets up the claude-code-cli-ide extension environment.
# - macOS: Installs/updates LaunchAgents (monitor + language updater)
# - Linux: Installs/updates systemd user services (monitor + language updater timer)
# - Verifies the server binary exists
#
# After running this, install the dev extension in Zed:
#   Command palette → "zed: install dev extension" → select ~/claude-code-cli-ide/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_ZED_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_BIN="$HOME/.local/bin/claude-code-server-zed"
PLATFORM="$(uname -s)"

MONITOR_LABEL="com.claude.zed-monitor"
LANGUAGES_LABEL="com.claude.zed-languages-update"

log() {
  echo "[claude-code-cli-ide install] $*"
}

# Ensure server binary exists — download from GitHub Releases if missing
download_server_binary() {
  local os arch asset_name repo url
  repo="beregcamlost/claude-code-cli-ide"

  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    *)      log "ERROR: Unsupported OS: $os"; exit 1 ;;
  esac

  case "$arch" in
    arm64|aarch64) arch="aarch64" ;;
    x86_64)        arch="x86_64" ;;
    *)             log "ERROR: Unsupported architecture: $arch"; exit 1 ;;
  esac

  asset_name="claude-code-server-${os}-${arch}.tar.gz"

  # Get latest release download URL
  url="https://github.com/${repo}/releases/latest/download/${asset_name}"

  log "Downloading server binary: $asset_name"
  mkdir -p "$HOME/.local/bin"

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  if ! curl -fSL --progress-bar -o "$tmpdir/$asset_name" "$url"; then
    log "ERROR: Failed to download $url"
    log "Check https://github.com/${repo}/releases for available binaries"
    exit 1
  fi

  tar -xzf "$tmpdir/$asset_name" -C "$tmpdir"
  mv "$tmpdir/claude-code-server" "$SERVER_BIN"
  chmod +x "$SERVER_BIN"
  log "Downloaded and installed: $SERVER_BIN"
}

if [[ ! -x "$SERVER_BIN" ]]; then
  log "Server binary not found at $SERVER_BIN — downloading from GitHub Releases"
  download_server_binary
fi
log "Server binary: $SERVER_BIN ($(ls -lh "$SERVER_BIN" | awk '{print $5}'))"

# ── macOS: LaunchAgents ──────────────────────────────────────────────

install_macos() {
  local launch_agents_dir="$HOME/Library/LaunchAgents"
  mkdir -p "$launch_agents_dir"

  install_plist() {
    local label="$1"
    local plist_src="$2"
    local plist_dst="$launch_agents_dir/${label}.plist"

    launchctl unload "$plist_dst" 2>/dev/null || true
    cp "$plist_src" "$plist_dst"
    launchctl load "$plist_dst"
    log "Installed and loaded: $label"
  }

  # Generate monitor plist
  local monitor_plist
  monitor_plist=$(mktemp)
  cat > "$monitor_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$MONITOR_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CC_ZED_DIR/scripts/monitor.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-zed-monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-zed-monitor.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin</string>
    </dict>
</dict>
</plist>
EOF
  install_plist "$MONITOR_LABEL" "$monitor_plist"
  rm "$monitor_plist"

  # Generate languages update plist
  local languages_plist
  languages_plist=$(mktemp)
  cat > "$languages_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LANGUAGES_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CC_ZED_DIR/scripts/update-languages.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/claude-zed-languages-update.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-zed-languages-update.log</string>
</dict>
</plist>
EOF
  install_plist "$LANGUAGES_LABEL" "$languages_plist"
  rm "$languages_plist"
}

# ── Linux: systemd user services ─────────────────────────────────────

install_linux() {
  local systemd_dir="$HOME/.config/systemd/user"
  mkdir -p "$systemd_dir"

  # Monitor service — restarts automatically
  cat > "$systemd_dir/claude-zed-monitor.service" <<EOF
[Unit]
Description=Claude Code Zed Monitor
After=graphical-session.target

[Service]
Type=simple
ExecStart=/bin/bash $CC_ZED_DIR/scripts/monitor.sh
Restart=always
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin:%h/.local/bin:%h/.cargo/bin

[Install]
WantedBy=default.target
EOF

  # Language updater service (oneshot, triggered by timer)
  cat > "$systemd_dir/claude-zed-languages-update.service" <<EOF
[Unit]
Description=Claude Code Zed Language List Updater

[Service]
Type=oneshot
ExecStart=/bin/bash $CC_ZED_DIR/scripts/update-languages.sh
Environment=PATH=/usr/local/bin:/usr/bin:/bin:%h/.local/bin:%h/.cargo/bin
EOF

  # Language updater timer — weekly on Sundays at 03:00
  cat > "$systemd_dir/claude-zed-languages-update.timer" <<EOF
[Unit]
Description=Weekly Claude Code Zed language list update

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload

  systemctl --user enable --now claude-zed-monitor.service
  log "Installed and started: claude-zed-monitor.service"

  systemctl --user enable --now claude-zed-languages-update.timer
  log "Installed and started: claude-zed-languages-update.timer"
}

# ── Main ─────────────────────────────────────────────────────────────

# Clean up old monitor script if it exists
OLD_MONITOR="$HOME/.local/bin/claude-zed-monitor"
if [[ -f "$OLD_MONITOR" ]]; then
  rm "$OLD_MONITOR"
  log "Removed old monitor script: $OLD_MONITOR"
fi

case "$PLATFORM" in
  Darwin)
    log "Detected macOS — installing LaunchAgents"
    install_macos
    ;;
  Linux)
    log "Detected Linux — installing systemd user services"
    install_linux
    ;;
  *)
    log "ERROR: Unsupported platform: $PLATFORM"
    log "Only macOS and Linux are supported"
    exit 1
    ;;
esac

log ""
log "Done! Next steps:"
log "  1. Open Zed"
log "  2. Command palette → 'zed: install dev extension'"
log "  3. Select: $CC_ZED_DIR"
