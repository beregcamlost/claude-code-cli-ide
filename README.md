<p align="center">
  <img src="https://img.shields.io/badge/Zed-Extension-4A90D9?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBkPSJNNCAyMEwyMCA0TTQgNEwyMCAyMCIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIyIi8+PC9zdmc+" alt="Zed Extension">
  <img src="https://img.shields.io/badge/Claude_Code-Integration-D97706?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/Rust-WASM-DEA584?style=for-the-badge&logo=rust&logoColor=white" alt="Rust WASM">
</p>

<h1 align="center">claude-code-cli-ide</h1>

<p align="center">
  <strong>A high-performance Zed extension that brings Claude Code directly into your editor.</strong>
  <br/>
  Built with Rust · Compiled to WASM · Powered by LSP + WebSocket
</p>

<p align="center">
  <img src="https://img.shields.io/github/license/beregcamlost/claude-code-cli-ide?style=flat-square&color=blue" alt="License">
  <img src="https://img.shields.io/github/v/release/beregcamlost/claude-code-cli-ide?style=flat-square&color=green" alt="Release">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-green?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/languages-65%2B-purple?style=flat-square" alt="Languages">
  <img src="https://img.shields.io/badge/zed_api-v0.7.0-orange?style=flat-square" alt="Zed API">
</p>

---

## What is this?

**claude-code-cli-ide** is a custom [Zed](https://zed.dev) extension that integrates [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as a language server. Unlike the marketplace extension, this one gives you **full control**:

| Feature | This ext | Marketplace |
|---------|:------:|:-----------:|
| Auto-download server binary | Yes | No |
| Hybrid mode (LSP + WebSocket) | Yes | No |
| Monitor daemon (auto start/stop) | Yes | No |
| Cross-platform (macOS + Linux) | Yes | Partial |
| WebSocket fallback (no file open) | Yes | No |
| Language list auto-updater | Yes | No |
| MCP tool providers | Yes | No |

---

## Architecture

```
                              Zed
  ┌────────────────────────────────────────────────────┐
  │  Extension (WASM)                                  │
  │  Registers as language server for 65+ languages    │
  │  1. Tries local binary on $PATH (dev workflow)     │
  │  2. Falls back to auto-download from GitHub        │
  └──────────────────────┬─────────────────────────────┘
                         │ stdio (LSP)
                         v
  ┌────────────────────────────────────────────────────┐
  │  claude-code-server-zed (native binary)            │
  │  ┌──────────┐  ┌─────────────┐  ┌──────────────┐  │
  │  │ LSP      │  │ WebSocket   │  │ MCP          │  │
  │  │ server   │<─┤ server      │  │ tools        │  │
  │  └──────────┘  └──────┬──────┘  └──────────────┘  │
  └───────────────────────┼────────────────────────────┘
                          │ ws://127.0.0.1:<port>
              ┌───────────v────────────────┐
              │  Claude Code CLI            │
              │  (connects via WebSocket)   │
              └────────────────────────────┘

  ┌─────────────────────────────────────────┐
  │  Monitor daemon (background service)    │
  │  Polls for Zed process -> starts/stops  │
  │  websocket-only server as fallback      │
  └─────────────────────────────────────────┘
```

> **Hybrid mode** (default): The extension starts the server with both an LSP channel (for Zed communication) and a WebSocket server (for Claude Code CLI). The monitor daemon provides a WebSocket-only fallback when no file is open.

---

## Marketplace Install

Install the extension from the Zed extension marketplace. The server binary is **automatically downloaded** for your platform on first use — no manual build required.

1. Open **Zed**
2. `Cmd+Shift+P` > **zed: extensions** > search **Claude Code CLI IDE**
3. Click **Install**
4. Open any file — the extension downloads the server binary and starts it

Supported platforms: macOS (Apple Silicon, Intel), Linux (x86_64, aarch64).

### Optional: Install services

The monitor daemon and language updater are optional background services:

```bash
git clone https://github.com/beregcamlost/claude-code-cli-ide.git ~/claude-code-cli-ide
bash ~/claude-code-cli-ide/scripts/install.sh
```

| Platform | Monitor | Language Updater |
|----------|---------|------------------|
| macOS | LaunchAgent `com.claude.zed-monitor` | LaunchAgent (weekly, Sun 03:00) |
| Linux | systemd `claude-zed-monitor.service` | systemd timer (weekly, Sun 03:00) |

---

## Dev Install

For local development, build the server binary yourself. The extension prefers a local binary on `$PATH` over the auto-downloaded one.

### Prerequisites

| Requirement | Details |
|-------------|---------|
| **Zed** | [zed.dev](https://zed.dev) |
| **Rust** | via [rustup](https://rustup.rs) (not homebrew) |
| **WASM target** | `rustup target add wasm32-wasip2` |
| **Claude Code** | [CLI installed](https://docs.anthropic.com/en/docs/claude-code) |

### Step 1 — Build the server binary

```bash
cd ~/claude-code-cli-ide/server
NATIVE_TARGET=$(rustc -vV | grep host | awk '{print $2}')
cargo build --release --target "$NATIVE_TARGET"
mkdir -p ~/.local/bin
cp "target/$NATIVE_TARGET/release/claude-code-server" ~/.local/bin/claude-code-server-zed
```

> Make sure `~/.local/bin` is on your `$PATH`

### Step 2 — Install services

```bash
bash ~/claude-code-cli-ide/scripts/install.sh
```

### Step 3 — Install the dev extension

1. Open **Zed**
2. `Cmd+Shift+P` > **zed: install dev extension**
3. Select `~/claude-code-cli-ide/`

> Zed builds the WASM extension automatically.

---

## How It Works

### Extension (WASM)

The extension (`src/lib.rs`) registers `claude-code-server` as a language server for **65+ languages** via `extension.toml`. When Zed opens a file:

1. Tries `worktree.which("claude-code-server-zed")` — uses local binary if found
2. If not on PATH: fetches latest GitHub release, downloads the platform-specific binary, caches it
3. Launches with `hybrid --worktree <path>` arguments
4. Sends initialization options (workspace folders, Claude Code metadata)

### Server Binary

The server (`server/`) runs in one of three modes:

| Mode | Started by | What it does |
|------|-----------|--------------|
| `hybrid` | Extension | LSP + WebSocket (full integration) |
| `websocket` | Monitor | WebSocket only (fallback) |
| `lsp` | Manual | LSP only (debugging) |

Lock files at `~/.claude/ide/<port>.lock` prevent port conflicts.

### Monitor Daemon

`scripts/monitor.sh` polls for the Zed process every second:

- **Zed starts** > launches `claude-code-server-zed websocket`
- **Zed exits** > stops the server and cleans up

### Language Updater

`scripts/update-languages.sh` fetches Zed's language list from source and diffs it against `extension.toml`. Reports additions/removals for manual review.

---

## Building from Source

### WASM Extension

```bash
cd ~/claude-code-cli-ide
cargo build --release
# .cargo/config.toml -> target = "wasm32-wasip2"
```

### Server Binary

> The root `.cargo/config.toml` targets `wasm32-wasip2`. Always pass `--target` for native builds.

```bash
cd ~/claude-code-cli-ide/server
NATIVE_TARGET=$(rustc -vV | grep host | awk '{print $2}')
cargo build --release --target "$NATIVE_TARGET"
cp "target/$NATIVE_TARGET/release/claude-code-server" ~/.local/bin/claude-code-server-zed
```

The server is a **separate crate** (native target, not WASM) with its own `Cargo.toml`. It is **not** part of the root workspace — they target different architectures.

---

## Creating a Release

1. Update version in `extension.toml`, `Cargo.toml`, and `server/Cargo.toml`
2. Commit: `git commit -m "chore: bump version to vX.Y.Z"`
3. Tag: `git tag vX.Y.Z`
4. Push: `git push origin main --tags`

GitHub Actions builds server binaries for all 4 platforms and attaches them to the release. The extension auto-downloads these binaries for marketplace users.

---

## Project Structure

```
claude-code-cli-ide/
├── .cargo/config.toml          WASM build target (wasm32-wasip2)
├── .github/workflows/
│   └── release.yml             CI: build server binaries on tag push
├── Cargo.toml                  Extension crate (cdylib)
├── extension.toml              Zed manifest (65+ languages)
│
├── src/
│   └── lib.rs                  Extension entry point (auto-download + fallback)
│
├── server/
│   ├── Cargo.toml              Standalone native crate
│   └── src/
│       ├── main.rs             CLI: hybrid | websocket | lsp
│       ├── lsp/
│       │   ├── server.rs       LSP backend (tower-lsp)
│       │   ├── handlers.rs     Request/notification handlers
│       │   ├── notifications.rs Notification bridge
│       │   ├── utils.rs        Utilities
│       │   └── watchdog.rs     Connection watchdog
│       ├── websocket.rs        WebSocket server (tokio-tungstenite)
│       └── mcp/
│           ├── server.rs       MCP server
│           ├── handlers.rs     MCP request handlers
│           ├── types.rs        MCP type definitions
│           └── tools/
│               ├── document.rs Document tools
│               ├── selection.rs Selection tools
│               └── workspace.rs Workspace tools
│
└── scripts/
    ├── install.sh              Service installer (macOS + Linux)
    ├── monitor.sh              Zed process monitor daemon
    └── update-languages.sh     Language list updater
```

---

## Troubleshooting

<details>
<summary><strong>Extension not loading</strong></summary>

Check the dev extension is installed:
- `Cmd+Shift+P` > **zed: installed extensions** > look for `claude-code-cli-ide`
- If missing: `Cmd+Shift+P` > **zed: install dev extension** > `~/claude-code-cli-ide/`

</details>

<details>
<summary><strong>Server not starting</strong></summary>

```bash
# Check binary is on PATH
which claude-code-server-zed

# Test manually
claude-code-server-zed --debug hybrid
```

</details>

<details>
<summary><strong>Lock file issues</strong></summary>

Lock files at `~/.claude/ide/<port>.lock`. If server crashed without cleanup:

```bash
# List stale lock files
ls -la ~/.claude/ide/*.lock

# Remove stale ones (check PID first)
rm ~/.claude/ide/<port>.lock
```

</details>

<details>
<summary><strong>Monitor service not working</strong></summary>

```bash
# macOS
cat /tmp/claude-zed-monitor.log
launchctl list | grep claude

# Linux
journalctl --user -u claude-zed-monitor.service -f
systemctl --user status claude-zed-monitor.service
```

</details>

<details>
<summary><strong>Language updater</strong></summary>

```bash
# macOS
cat /tmp/claude-zed-languages-update.log

# Linux
journalctl --user -u claude-zed-languages-update.service
systemctl --user status claude-zed-languages-update.timer
```

</details>

<details>
<summary><strong>Broken symlink after directory rename</strong></summary>

If you renamed the project directory (e.g. `cc-zed` → `claude-code-cli-ide`), the dev extension symlink will point to the old path.

**Symptoms:** Extension not loading, LaunchAgents exit code 127.

**Fix:**

```bash
# Remove broken symlink
rm ~/Library/Application\ Support/Zed/extensions/installed/claude-code-cli-ide

# Re-install dev extension
# Cmd+Shift+P > "zed: install dev extension" > select new directory

# Re-run install.sh to update LaunchAgent paths
bash ~/claude-code-cli-ide/scripts/install.sh

# Restart Claude Code CLI (it discovers lock files at startup)
```

</details>

---

## Platform Support

| Platform | Status | Service Manager |
|----------|--------|-----------------|
| macOS | Full | LaunchAgents |
| Linux | Full | systemd user services |
| Windows | Not supported | Zed has limited Windows support |

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">
  <sub>Built with Rust + Zed Extension API + Claude Code</sub>
</p>
