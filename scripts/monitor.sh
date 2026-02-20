#!/usr/bin/env bash
# monitor.sh: Polls for the Zed editor process and manages
# the claude-code-server-zed lifecycle (start on Zed open, stop on Zed close).
# Provides WebSocket-only fallback when no file is open in Zed.
# Designed to run as a macOS LaunchAgent or Linux systemd user service.

set -euo pipefail

SERVER_BIN="$HOME/.local/bin/claude-code-server-zed"
SERVER_PID=""
POLL_INTERVAL=1

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [zed-monitor] $*"
}

cleanup() {
  log "Monitor shutting down"
  kill_server
  exit 0
}

trap cleanup SIGTERM SIGINT

is_zed_running() {
  # macOS: process is "zed", Linux: can be "zed" or "zed-editor" (Flatpak/AppImage)
  pgrep -x "zed" > /dev/null 2>&1 || pgrep -x "zed-editor" > /dev/null 2>&1
}

is_server_running() {
  [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null
}

start_server() {
  log "Zed detected, starting claude-code-server-zed websocket"
  "$SERVER_BIN" websocket &
  SERVER_PID=$!
  log "Server started (PID $SERVER_PID)"
}

kill_server() {
  if is_server_running; then
    log "Stopping server (PID $SERVER_PID)"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    log "Server stopped"
  fi
}

log "Monitor started (PID $$)"

while true; do
  if is_zed_running; then
    if ! is_server_running; then
      start_server
    fi
  else
    if is_server_running; then
      log "Zed exited, stopping server"
      kill_server
    fi
  fi
  sleep "$POLL_INTERVAL"
done
