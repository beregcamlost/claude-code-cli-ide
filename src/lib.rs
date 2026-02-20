use zed_extension_api::{
    self as zed, serde_json, Command, DownloadedFileType, GithubReleaseOptions, LanguageServerId,
    LanguageServerInstallationStatus, Result, Worktree,
};

const SERVER_BINARY: &str = "claude-code-server-zed";
const GITHUB_REPO: &str = "beregcamlost/claude-code-cli-ide";
const EXTENSION_VERSION: &str = "0.1.1";

struct ClaudeCodeExtension;

impl ClaudeCodeExtension {
    fn asset_name(os: zed::Os, arch: zed::Architecture) -> std::result::Result<String, String> {
        let os_str = match os {
            zed::Os::Mac => "darwin",
            zed::Os::Linux => "linux",
            _ => return Err("Unsupported OS — only macOS and Linux are supported".into()),
        };
        let arch_str = match arch {
            zed::Architecture::Aarch64 => "aarch64",
            zed::Architecture::X8664 => "x86_64",
            _ => return Err("Unsupported architecture — only aarch64 and x86_64 are supported".into()),
        };
        Ok(format!("claude-code-server-{os_str}-{arch_str}.tar.gz"))
    }

    fn download_server(
        &self,
        language_server_id: &LanguageServerId,
    ) -> std::result::Result<String, String> {
        let (os, arch) = zed::current_platform();
        let asset_name = Self::asset_name(os, arch)?;

        let release = zed::latest_github_release(
            GITHUB_REPO,
            GithubReleaseOptions {
                require_assets: true,
                pre_release: false,
            },
        )?;

        let version_dir = format!("download/{}", release.version);
        let binary_path = format!("{version_dir}/claude-code-server");

        if std::fs::metadata(&binary_path).is_ok() {
            return Ok(binary_path);
        }

        let asset = release
            .assets
            .iter()
            .find(|a| a.name == asset_name)
            .ok_or_else(|| {
                format!(
                    "No asset '{asset_name}' found in release {}",
                    release.version
                )
            })?;

        zed::set_language_server_installation_status(
            language_server_id,
            &LanguageServerInstallationStatus::Downloading,
        );

        zed::download_file(
            &asset.download_url,
            &version_dir,
            DownloadedFileType::GzipTar,
        )
        .map_err(|e| format!("Failed to download server binary: {e}"))?;

        zed::make_file_executable(&binary_path)
            .map_err(|e| format!("Failed to make binary executable: {e}"))?;

        zed::set_language_server_installation_status(
            language_server_id,
            &LanguageServerInstallationStatus::None,
        );

        Ok(binary_path)
    }
}

impl zed::Extension for ClaudeCodeExtension {
    fn new() -> Self {
        ClaudeCodeExtension
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Command> {
        // Prefer local binary on $PATH (dev workflow)
        let binary_path = if let Some(path) = worktree.which(SERVER_BINARY) {
            path
        } else {
            // Auto-download from GitHub Releases
            self.download_server(language_server_id)?
        };

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
