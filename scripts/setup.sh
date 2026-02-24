#!/usr/bin/env bash
# setup.sh: One-command full dev setup for claude-code-cli-ide.
# Cleans old installs, builds the server binary, installs services.
#
# Usage:
#   bash ~/claude-code-cli-ide/scripts/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_ZED_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_BIN="$HOME/.local/bin/claude-code-server-zed"
PLATFORM="$(uname -s)"

MONITOR_LABEL="com.claude.zed-monitor"
LANGUAGES_LABEL="com.claude.zed-languages-update"

log() {
  echo "[claude-code-cli-ide setup] $*"
}

# ── Cleanup ──────────────────────────────────────────────────────────

cleanup() {
  log "=== Cleanup ==="

  # Kill running claude-code-server-zed processes
  if pgrep -f "claude-code-server-zed" > /dev/null 2>&1; then
    log "Stopping running claude-code-server-zed processes"
    pkill -f "claude-code-server-zed" 2>/dev/null || true
    sleep 1
  fi

  # Remove broken Zed extension symlink
  local ext_dir
  case "$PLATFORM" in
    Darwin) ext_dir="$HOME/Library/Application Support/Zed/extensions/installed/claude-code-cli-ide" ;;
    Linux)  ext_dir="$HOME/.local/share/zed/extensions/installed/claude-code-cli-ide" ;;
  esac

  if [[ -n "${ext_dir:-}" && -L "$ext_dir" && ! -e "$ext_dir" ]]; then
    rm "$ext_dir"
    log "Removed broken extension symlink: $ext_dir"
  fi

  # Remove old server binary
  if [[ -f "$SERVER_BIN" ]]; then
    rm "$SERVER_BIN"
    log "Removed old server binary: $SERVER_BIN"
  fi

  # Clean stale lock files (only if owning process is dead)
  local lock_dir="$HOME/.claude/ide"
  if [[ -d "$lock_dir" ]]; then
    for lockfile in "$lock_dir"/*.lock; do
      [[ -f "$lockfile" ]] || continue
      local pid
      pid="$(cat "$lockfile" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        rm "$lockfile"
        log "Removed stale lock file: $lockfile (PID $pid dead)"
      fi
    done
  fi

  # Platform-specific service cleanup
  case "$PLATFORM" in
    Darwin)
      cleanup_macos
      ;;
    Linux)
      cleanup_linux
      ;;
  esac
}

cleanup_macos() {
  local launch_agents_dir="$HOME/Library/LaunchAgents"

  for label in "$MONITOR_LABEL" "$LANGUAGES_LABEL"; do
    local plist="$launch_agents_dir/${label}.plist"
    if [[ -f "$plist" ]]; then
      launchctl unload "$plist" 2>/dev/null || true
      rm "$plist"
      log "Removed LaunchAgent: $label"
    fi
  done
}

cleanup_linux() {
  local systemd_dir="$HOME/.config/systemd/user"

  for unit in claude-zed-monitor.service claude-zed-languages-update.service claude-zed-languages-update.timer; do
    if systemctl --user is-active "$unit" > /dev/null 2>&1; then
      systemctl --user stop "$unit" 2>/dev/null || true
    fi
    systemctl --user disable "$unit" 2>/dev/null || true
    if [[ -f "$systemd_dir/$unit" ]]; then
      rm "$systemd_dir/$unit"
      log "Removed systemd unit: $unit"
    fi
  done
  systemctl --user daemon-reload 2>/dev/null || true
}

# ── Install ──────────────────────────────────────────────────────────

install_rust() {
  if command -v rustc > /dev/null 2>&1; then
    log "Rust found: $(rustc --version)"
    return
  fi

  log "Rust not found."
  read -rp "Install Rust via rustup? [Y/n] " answer
  case "${answer:-Y}" in
    [Yy]*)
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      # shellcheck disable=SC1091
      source "$HOME/.cargo/env"
      log "Rust installed: $(rustc --version)"
      ;;
    *)
      log "ERROR: Rust is required. Install from https://rustup.rs"
      exit 1
      ;;
  esac
}

add_wasm_target() {
  if rustup target list --installed | grep -q "wasm32-wasip2"; then
    log "WASM target already installed"
  else
    log "Adding wasm32-wasip2 target"
    rustup target add wasm32-wasip2
  fi
}

build_server() {
  log "=== Building server binary ==="

  local native_target
  native_target="$(rustc -vV | grep host | awk '{print $2}')"

  log "Target: $native_target"
  (cd "$CC_ZED_DIR/server" && cargo build --release --target "$native_target")

  mkdir -p "$HOME/.local/bin"
  cp "$CC_ZED_DIR/server/target/$native_target/release/claude-code-server" "$SERVER_BIN"
  chmod +x "$SERVER_BIN"

  log "Installed: $SERVER_BIN ($(ls -lh "$SERVER_BIN" | awk '{print $5}'))"
}

check_path() {
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    log ""
    log "WARNING: ~/.local/bin is not on your \$PATH"
    log "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    log "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

# ── Main ─────────────────────────────────────────────────────────────

log "=== claude-code-cli-ide dev setup ==="
log "Project: $CC_ZED_DIR"
log ""

cleanup

log ""
log "=== Install ==="

install_rust
add_wasm_target
build_server
check_path

log ""
log "=== Services ==="

bash "$SCRIPT_DIR/install.sh"

log ""
log "=== Done ==="
log ""
log "Next step: Install the dev extension in Zed"
log "  1. Open Zed"
log "  2. Cmd+Shift+P > 'zed: install dev extension'"
log "  3. Select: $CC_ZED_DIR"
