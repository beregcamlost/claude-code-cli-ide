#!/usr/bin/env bash
# update-languages.sh — Fetches Zed's built-in language list and updates extension.toml
# Designed to run weekly via LaunchAgent or manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSION_TOML="$SCRIPT_DIR/../extension.toml"
LOG_PREFIX="[update-languages]"
ZED_LANGUAGES_URL="https://raw.githubusercontent.com/zed-industries/zed/main/crates/languages/src/lib.rs"

log() { echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Fetch language names from Zed's source
fetch_zed_languages() {
    local raw
    raw=$(curl -sS --max-time 30 "$ZED_LANGUAGES_URL" 2>/dev/null) || {
        log "ERROR: Failed to fetch Zed languages source"
        return 1
    }

    # Extract language names from the Rust source — looks for patterns like:
    #   "language_name" or language identifiers in the registration arrays
    # This is a best-effort heuristic; the canonical list is what we already have.
    echo "$raw" | grep -oE '"[A-Za-z][A-Za-z0-9 +#]*"' | tr -d '"' | sort -u
}

# Extract current languages from extension.toml
current_languages() {
    sed -n '/^languages = \[/,/^\]/p' "$EXTENSION_TOML" \
        | grep -oE '"[^"]+"' \
        | tr -d '"' \
        | sort
}

# Main
log "Starting language list check"

NEW_LANGS=$(fetch_zed_languages) || exit 1
CURRENT_LANGS=$(current_languages)

DIFF=$(diff <(echo "$CURRENT_LANGS") <(echo "$NEW_LANGS") || true)

if [[ -z "$DIFF" ]]; then
    log "No changes detected — language list is up to date"
    exit 0
fi

log "Differences found:"
echo "$DIFF"
log "NOTE: Auto-update of extension.toml is not yet implemented."
log "Review the diff above and manually update extension.toml if needed."
log "New languages from Zed source that may need adding:"
comm -13 <(echo "$CURRENT_LANGS") <(echo "$NEW_LANGS") | while read -r lang; do
    log "  + $lang"
done
log "Languages in extension.toml not found in Zed source (may be fine — custom additions):"
comm -23 <(echo "$CURRENT_LANGS") <(echo "$NEW_LANGS") | while read -r lang; do
    log "  - $lang"
done
