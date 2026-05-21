#!/usr/bin/env bash
# ============================================================
#  Claude Code Portable - macOS / Linux Launcher
#  https://github.com/anthropics/claude-code (official)
# ============================================================

set -euo pipefail

# ---- Portable root = directory of this script ----
ROOT="$(cd "$(dirname "$0")" && pwd)"

# ---- Directory layout ----
BIN_DIR="$ROOT/bin"
DATA_DIR="$ROOT/data"
TMP_DIR="$ROOT/tmp"
GIT_DIR="$ROOT/git"

# ---- Official download source ----
GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# ============================================================
#  Functions (must be defined before use)
# ============================================================

show_help() {
    cat <<'HELP'

  Claude Code Portable
  ====================

  Usage:
    ./claude.sh                  Launch Claude Code in current directory
    ./claude.sh [folder]         Launch in specified folder
    ./claude.sh update           Download the latest Claude Code version
    ./claude.sh update [version] Download a specific version (e.g. 2.1.80)
    ./claude.sh setup            Pre-download everything for offline use
    ./claude.sh doctor           Diagnose installation and environment
    ./claude.sh version          Show installed version
    ./claude.sh --help           Show this help

  Structure:
    config                       API key / proxy settings (optional)
    data/                        Portable config, auth, agents, memory
    bin/                         Claude Code binary (auto-downloaded)
    tmp/                         Temporary files

HELP
}

check_online() {
    # Any HTTP response (even 400) means we're online. Only connection failures mean offline.
    if curl -sS --head --connect-timeout 5 "https://storage.googleapis.com" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *)
            echo "  [Error] Unsupported OS: $os"
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64|amd64)  arch="x64" ;;
        arm64|aarch64) arch="arm64" ;;
        *)
            echo "  [Error] Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    # Detect musl (Alpine, etc.)
    local libc=""
    if [ "$os" = "linux" ]; then
        if ldd --version 2>&1 | grep -qi musl; then
            libc="-musl"
        fi
    fi

    echo "${os}-${arch}${libc}"
}

download_claude() {
    local platform pin_version="${1:-}"
    platform="$(detect_platform)"

    local version
    if [ -n "$pin_version" ]; then
        version="$pin_version"
        echo "  Requested: v${version} (${platform})"
    else
        echo "  Fetching latest version..."
        version="$(curl -fsSL "$GCS_BUCKET/latest")"
        if [ -z "$version" ]; then
            echo "  [Error] Could not reach download server. Check your internet."
            return 1
        fi
        echo "  Latest: v${version} (${platform})"
    fi

    # Fetch checksum from manifest
    local manifest expected
    manifest="$(curl -fsSL "$GCS_BUCKET/$version/manifest.json")"
    if [ -z "$manifest" ]; then
        echo "  [Error] Could not fetch release manifest. Version may not exist."
        return 1
    fi

    # Parse JSON - try python3, jq, then grep fallback
    if command -v python3 &>/dev/null; then
        expected="$(echo "$manifest" | python3 -c "import sys,json; print(json.load(sys.stdin)['platforms']['$platform']['checksum'])")"
    elif command -v jq &>/dev/null; then
        expected="$(echo "$manifest" | jq -r ".platforms.\"$platform\".checksum")"
    else
        expected="$(echo "$manifest" | grep -A2 "\"$platform\"" | grep '"checksum"' | sed 's/.*"checksum"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/')"
    fi

    if [ -z "$expected" ]; then
        echo "  [Error] Could not parse checksum for $platform."
        return 1
    fi

    # Download binary
    echo "  Downloading claude..."
    curl -fSL "$GCS_BUCKET/$version/$platform/claude" -o "$BIN_DIR/claude"
    if [ ! -f "$BIN_DIR/claude" ]; then
        echo "  [Error] Download failed."
        return 1
    fi

    # Verify SHA256
    echo "  Verifying checksum..."
    local actual
    if command -v sha256sum &>/dev/null; then
        actual="$(sha256sum "$BIN_DIR/claude" | awk '{print $1}')"
    elif command -v shasum &>/dev/null; then
        actual="$(shasum -a 256 "$BIN_DIR/claude" | awk '{print $1}')"
    else
        echo "  [Warning] No SHA256 tool found, skipping verification."
        actual="$expected"
    fi

    if [ "$actual" != "$expected" ]; then
        echo "  [Error] Checksum mismatch!"
        echo "    Expected: $expected"
        echo "    Got:      $actual"
        rm -f "$BIN_DIR/claude"
        return 1
    fi

    chmod +x "$BIN_DIR/claude"
    echo "$version" > "$BIN_DIR/.version"
    echo "  Claude Code v${version} ready."
    echo
}

# ============================================================
#  Main
# ============================================================

# Create directories
mkdir -p "$BIN_DIR" "$DATA_DIR" "$TMP_DIR"

# Create default CLAUDE.md if missing
if [ ! -f "$DATA_DIR/CLAUDE.md" ]; then
    cat > "$DATA_DIR/CLAUDE.md" <<'CLAUDEMD'
# Portable Environment

This is a portable Claude Code installation. All configuration and state
is stored in this folder's data/ directory, not in ~/.claude/.

- Auto-updates are disabled. Update manually: `.\\claude.ps1 update` or `./claude.sh update`
- Do not suggest modifying ~/.claude/ - this install uses a custom CLAUDE_CONFIG_DIR.
CLAUDEMD
fi

# Handle commands
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    version|--version|-v)
        if [ -f "$BIN_DIR/.version" ]; then
            echo "  Claude Code Portable v$(cat "$BIN_DIR/.version")"
        else
            echo "  Claude Code not yet downloaded. Run ./claude.sh to install."
        fi
        exit 0
        ;;
    update)
        echo
        if [ -f "$BIN_DIR/.version" ]; then
            echo "  Current version: v$(cat "$BIN_DIR/.version")"
        fi
        if ! check_online; then
            echo "  [Error] No internet connection. Cannot update."
            exit 1
        fi
        rm -f "$BIN_DIR/claude"
        download_claude "${2:-}"
        echo "  Update complete!"
        exit 0
        ;;
    setup)
        echo
        echo "  Claude Code Portable - Offline Setup"
        echo "  ====================================="
        echo "  Pre-downloads everything so this drive works offline."
        echo
        if ! check_online; then
            echo "  [Error] No internet connection. Run setup on a machine with internet."
            exit 1
        fi
        # Download Claude Code if needed
        if [ ! -x "$BIN_DIR/claude" ]; then
            download_claude
        else
            echo "  Claude Code v$(cat "$BIN_DIR/.version") already downloaded."
        fi
        echo
        echo "  Setup complete! This drive is ready for offline use."
        exit 0
        ;;
    doctor)
        echo
        echo "  Claude Code Portable - Diagnostics"
        echo "  =================================="
        echo
        issues=0
        warns=0

        # Check directories
        for d in "$BIN_DIR" "$DATA_DIR" "$TMP_DIR"; do
            name=$(basename "$d")
            if [ -d "$d" ]; then
                if [ -w "$d" ]; then
                    echo "  [OK]    Directory exists and writable: $name/"
                else
                    echo "  [WARN]  Directory exists but not writable: $name/"
                    warns=$((warns + 1))
                fi
            else
                echo "  [MISS]  Directory missing: $name/"
                issues=$((issues + 1))
            fi
        done

        # Check binary
        if [ -f "$BIN_DIR/claude" ]; then
            size=$(stat -f%z "$BIN_DIR/claude" 2>/dev/null || stat -c%s "$BIN_DIR/claude" 2>/dev/null || echo 0)
            if [ "$size" -gt 0 ]; then
                size_mb=$((size / 1024 / 1024))
                echo "  [OK]    Binary found (${size_mb} MB)"
                if [ -f "$BIN_DIR/.version" ]; then
                    ver=$(cat "$BIN_DIR/.version")
                    echo "  [OK]    Version: v$ver"
                else
                    echo "  [WARN]  Binary found but .version file missing"
                    warns=$((warns + 1))
                fi
            else
                echo "  [FAIL]  Binary is empty (0 bytes)"
                issues=$((issues + 1))
            fi
        else
            echo "  [MISS]  Binary not found in bin/"
            issues=$((issues + 1))
        fi

        # Check Git
        if command -v git &>/dev/null; then
            git_path=$(command -v git)
            echo "  [OK]    Git found: $git_path"
        else
            echo "  [MISS]  Git not found in PATH"
            echo "          Install Git or ensure it is available."
            issues=$((issues + 1))
        fi

        # Check config
        if [ -f "$ROOT/config" ]; then
            config_issues=0
            line_num=0
            while IFS= read -r line; do
                line_num=$((line_num + 1))
                line_trimmed=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$line_trimmed" ] && continue
                case "$line_trimmed" in
                    \#*) continue ;;
                esac
                if ! echo "$line_trimmed" | grep -q '='; then
                    echo "  [WARN]  Config line $line_num may be malformed: $line"
                    config_issues=$((config_issues + 1))
                fi
            done < "$ROOT/config"
            if [ "$config_issues" -eq 0 ]; then
                echo "  [OK]    Config file syntax valid"
            else
                warns=$((warns + config_issues))
            fi
        else
            echo "  [INFO]  No config file (optional - browser login works without it)"
        fi

        # Check disk space
        free_mb=$(df -m "$ROOT" | awk 'NR==2 {print $4}')
        free_gb=$((free_mb / 1024))
        if [ "$free_gb" -gt 1 ]; then
            echo "  [OK]    Free space: ${free_gb} GB"
        else
            echo "  [WARN]  Low disk space: ${free_gb} GB"
            warns=$((warns + 1))
        fi

        # Check online
        if check_online; then
            echo "  [OK]    Internet connection available"
        else
            echo "  [WARN]  No internet connection detected"
            warns=$((warns + 1))
        fi

        echo
        if [ "$issues" -eq 0 ] && [ "$warns" -eq 0 ]; then
            echo "  All checks passed."
        elif [ "$issues" -eq 0 ]; then
            echo "  All critical checks passed. ${warns} warning(s) found."
        else
            echo "  Found ${issues} issue(s) and ${warns} warning(s). See details above."
        fi
        echo
        exit 0
        ;;
esac

# Load config if it exists (optional - OAuth works without it)
if [ -f "$ROOT/config" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            \#*|"") continue ;;
        esac
        if [ -n "$value" ]; then
            export "$key=$value"
        fi
    done < "$ROOT/config"
fi

# Download Claude Code if needed
if [ ! -x "$BIN_DIR/claude" ]; then
    if ! check_online; then
        echo "  [Error] No internet connection. Cannot download Claude Code."
        echo "  Connect to the internet and try again."
        exit 1
    fi
    download_claude
fi

# Offline banner
if ! check_online; then
    echo "  [Offline] No internet connection detected."
    echo "  Claude Code will run, but authentication and API calls may fail"
    echo "  if your credentials have expired."
    echo
fi

# Set portable environment
export CLAUDE_CONFIG_DIR="$DATA_DIR"
export CLAUDE_CODE_TMPDIR="$TMP_DIR"
export DISABLE_AUTOUPDATER=1

# Use portable git if present
if [ -d "$GIT_DIR/bin" ]; then
    export PATH="$GIT_DIR/bin:$PATH"
fi

# Handle directory argument
if [ -n "${1:-}" ] && [ -d "$1" ]; then
    cd "$1"
    shift
fi

# Launch
exec "$BIN_DIR/claude" "$@"
