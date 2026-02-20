use zed_extension_api::{self as zed, serde_json, Command, LanguageServerId, Result, Worktree};

const SERVER_BINARY: &str = "claude-code-server-zed";
const EXTENSION_VERSION: &str = "0.1.0";

struct ClaudeCodeExtension;

impl zed::Extension for ClaudeCodeExtension {
    fn new() -> Self {
        ClaudeCodeExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Command> {
        let binary_path = worktree.which(SERVER_BINARY).ok_or_else(|| {
            format!(
                "{SERVER_BINARY} not found on $PATH. \
                 Build it: cd cc-zed/server && cargo build --release && \
                 cp target/release/claude-code-server ~/.local/bin/{SERVER_BINARY}"
            )
        })?;

        let worktree_path = worktree.root_path();

        Ok(Command {
            command: binary_path,
            args: vec![
                "--debug".to_string(),
                "--worktree".to_string(),
                worktree_path.to_string(),
                "hybrid".to_string(),
            ],
            env: vec![],
        })
    }

    fn language_server_initialization_options(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Option<serde_json::Value>> {
        let worktree_path = worktree.root_path();
        let name = worktree_path
            .split('/')
            .last()
            .unwrap_or(&worktree_path);

        Ok(Some(serde_json::json!({
            "workspaceFolders": [{
                "uri": format!("file://{}", worktree_path),
                "name": name,
            }],
            "claudeCode": {
                "enabled": true,
                "extensionVersion": EXTENSION_VERSION,
                "ideName": "Zed",
            }
        })))
    }

    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &LanguageServerId,
        _worktree: &Worktree,
    ) -> Result<Option<serde_json::Value>> {
        Ok(Some(serde_json::json!({
            "claudeCode": {
                "enabled": true,
                "debug": true,
                "websocket": {
                    "host": "127.0.0.1",
                    "portRange": [10000, 65535],
                },
                "auth": {
                    "generateTokens": true,
                }
            }
        })))
    }
}

zed::register_extension!(ClaudeCodeExtension);
