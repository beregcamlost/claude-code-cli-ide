# cc-zed

A custom [Zed](https://zed.dev) extension that integrates [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as a language server. Unlike the marketplace extension ([celve/claude-code-zed](https://github.com/nicholasgasior/claude-code-zed)), this one:

- Runs a **locally-built** server binary — no downloads, no auto-updates
- Supports **hybrid mode** (LSP + WebSocket) for full IDE integration
- Includes a **monitor daemon** that provides WebSocket fallback when no file is open
- Ships a **language updater** script that tracks Zed's built-in language list
- Works on **macOS and Linux**

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                       Zed                           │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  cc-zed extension (WASM)                      │  │
│  │  Registers as language server for 65+ langs   │  │
│  │  Finds claude-code-server-zed on $PATH        │  │
│  │  Launches: hybrid --worktree <path>           │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │ stdio (LSP)                    │
│                     ▼                                │
│  ┌───────────────────────────────────────────────┐  │
│  │  claude-code-server-zed (native binary)       │  │
│  │  ┌─────────┐  ┌────────────┐  ┌───────────┐  │  │
│  │  │   LSP   │  │ WebSocket  │  │    MCP    │  │  │
│  │  │ server  │◄─┤  server    │  │  tools    │  │  │
│  │  └─────────┘  └──────┬─────┘  └───────────┘  │  │
│  └───────────────────────┼───────────────────────┘  │
│                          │ ws://127.0.0.1:<port>     │
└──────────────────────────┼──────────────────────────┘
                           │
              ┌────────────▼────────────────┐
              │     Claude Code CLI          │
              │     (connects via WebSocket) │
              └─────────────────────────────┘

  ┌────────────────────────────────────────┐
  │  Monitor daemon (background service)   │
  │  Polls for Zed process → starts/stops  │
  │  websocket-only server as fallback     │
  └────────────────────────────────────────┘
```

**Hybrid mode** (default): The extension starts the server with both an LSP channel (for Zed communication) and a WebSocket server (for Claude Code CLI). The monitor daemon provides a WebSocket-only fallback when no file is open in Zed and the extension hasn't started a server.

## Prerequisites

- [Zed](https://zed.dev) editor
- [Rust](https://rustup.rs) toolchain
- WASM target: `rustup target add wasm32-wasip2`
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed

## Quick install

### 1. Build the server binary

The server is a native binary but lives inside the WASM-targeted project. Use `--target` to build for your platform:

```bash
cd ~/cc-zed/server
NATIVE_TARGET=$(rustc -vV | grep host | awk '{print $2}')
cargo build --release --target "$NATIVE_TARGET"
mkdir -p ~/.local/bin
cp "target/$NATIVE_TARGET/release/claude-code-server" ~/.local/bin/claude-code-server-zed
```

Make sure `~/.local/bin` is on your `$PATH`.

### 2. Install services

```bash
bash ~/cc-zed/scripts/install.sh
```

This sets up:

| Platform | Monitor | Language updater |
|----------|---------|------------------|
| macOS    | LaunchAgent (`com.claude.zed-monitor`) | LaunchAgent (weekly, Sundays 03:00) |
| Linux    | systemd user service (`claude-zed-monitor.service`) | systemd timer (weekly, Sundays 03:00) |

### 3. Install the extension in Zed

1. Open Zed
2. Command palette → **zed: install dev extension**
3. Select `~/cc-zed/`

Zed will build the WASM extension automatically.

## Building from source

### WASM extension

```bash
cd ~/cc-zed
cargo build --release
```

The `.cargo/config.toml` sets the build target to `wasm32-wasip2`. Zed picks up the compiled extension automatically when installed as a dev extension.

### Server binary

The root `.cargo/config.toml` sets the target to `wasm32-wasip2`, so you must pass `--target` explicitly when building the server:

```bash
cd ~/cc-zed/server
NATIVE_TARGET=$(rustc -vV | grep host | awk '{print $2}')
cargo build --release --target "$NATIVE_TARGET"
cp "target/$NATIVE_TARGET/release/claude-code-server" ~/.local/bin/claude-code-server-zed
```

The server is a separate crate (native target, not WASM) with its own `Cargo.toml`. It is **not** part of the root workspace — they target different architectures.

## How it works

### Extension (WASM)

The extension (`src/lib.rs`) registers `claude-code-server` as a language server for 65+ languages in `extension.toml`. When Zed opens a file in any of those languages, it calls `language_server_command()` which:

1. Uses `worktree.which("claude-code-server-zed")` to find the binary on `$PATH`
2. Launches it with `hybrid --worktree <path>` arguments
3. Sends initialization options (workspace folders, Claude Code metadata)

### Server binary

The server (`server/`) runs in one of three modes:

- **`hybrid`** (default from extension) — LSP + WebSocket. The LSP channel communicates with Zed, the WebSocket channel connects to Claude Code CLI.
- **`websocket`** (from monitor) — WebSocket only. Fallback when no file is open.
- **`lsp`** — LSP only. For debugging.

Lock files are created at `~/.claude/ide/<port>.lock` to prevent port conflicts.

### Monitor daemon

`scripts/monitor.sh` polls for the Zed process every second:

- Zed starts → launches `claude-code-server-zed websocket`
- Zed exits → stops the server and cleans up

### Language updater

`scripts/update-languages.sh` fetches Zed's language list from source and diffs it against `extension.toml`. Reports additions/removals for manual review.

## File structure

```
cc-zed/
├── .cargo/config.toml        # WASM build target (wasm32-wasip2)
├── Cargo.toml                 # Extension crate (cdylib)
├── extension.toml             # Zed extension manifest (65+ languages)
├── src/
│   └── lib.rs                 # Extension entry point
├── server/
│   ├── Cargo.toml             # Server crate (standalone, native target)
│   └── src/
│       ├── main.rs            # CLI: hybrid | websocket | lsp modes
│       ├── lsp/               # LSP server (tower-lsp)
│       │   ├── server.rs      # Backend implementation
│       │   ├── handlers.rs    # Request/notification handlers
│       │   ├── notifications.rs
│       │   ├── utils.rs
│       │   └── watchdog.rs
│       ├── websocket.rs       # WebSocket server (tokio-tungstenite)
│       └── mcp/               # MCP tool providers
│           ├── server.rs
│           ├── handlers.rs
│           ├── types.rs
│           └── tools/
│               ├── document.rs
│               ├── selection.rs
│               └── workspace.rs
└── scripts/
    ├── install.sh             # Service installer (macOS + Linux)
    ├── monitor.sh             # Zed process monitor daemon
    └── update-languages.sh    # Language list updater
```

## Troubleshooting

### Extension not loading

Check that the dev extension is installed:
- Command palette → **zed: installed extensions** → look for `cc-zed`
- If missing, reinstall: command palette → **zed: install dev extension** → `~/cc-zed/`

### Server not starting

```bash
# Check the binary is on PATH
which claude-code-server-zed

# Test it manually
claude-code-server-zed --debug hybrid
```

### Lock file issues

Lock files live at `~/.claude/ide/<port>.lock`. If a server crashes without cleanup:

```bash
# List stale lock files
ls -la ~/.claude/ide/*.lock

# Remove stale ones (check PID first)
rm ~/.claude/ide/<port>.lock
```

### Monitor service

```bash
# macOS
cat /tmp/claude-zed-monitor.log
launchctl list | grep claude

# Linux
journalctl --user -u claude-zed-monitor.service -f
systemctl --user status claude-zed-monitor.service
```

### Language updater

```bash
# macOS
cat /tmp/claude-zed-languages-update.log

# Linux
journalctl --user -u claude-zed-languages-update.service
systemctl --user status claude-zed-languages-update.timer
```

## Platform support

| Platform | Status | Service manager |
|----------|--------|-----------------|
| macOS    | Full   | LaunchAgents    |
| Linux    | Full   | systemd user services |
| Windows  | Not supported | Zed has limited Windows support |

## License

MIT — see [LICENSE](LICENSE).
