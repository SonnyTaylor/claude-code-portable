# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A portable launcher for Claude Code that runs from a USB drive or any folder with no installation. Three launcher scripts (`claude.ps1` as the primary Windows launcher, `claude.cmd` as the Windows fallback, and `claude.sh` for macOS/Linux) download the official Claude Code binary, optionally download Portable Git (Windows only), and configure environment variables so all state stays within this folder.

## Architecture

The project has no build system, tests, or dependencies -- it is purely shell scripts.

- `claude.ps1` - Primary Windows launcher (PowerShell, uses `Invoke-WebRequest` for downloads, `Get-FileHash` for SHA256 verification)
- `claude.cmd` - Windows batch fallback launcher (used when PowerShell is unavailable; auto-forwards to `claude.ps1` when possible)
- `claude.sh` - macOS/Linux bash launcher (uses `curl` for downloads, `sha256sum`/`shasum` for verification)
- `config.example` - Template for optional API key / proxy configuration
- `data/CLAUDE.md` - Auto-generated starter CLAUDE.md placed into the portable config directory by the launcher scripts on first run

All three launchers share identical logic:
1. Create `bin/`, `data/`, `tmp/` directories
2. Create a default `data/CLAUDE.md` if missing
3. Handle subcommands (`update`, `version`, `setup`, `--help`)
4. Load `config` file (key=value pairs) into environment if it exists
5. Download Claude Code binary from GCS bucket with SHA256 verification if not present
6. On Windows: find or download Portable Git
7. Set `CLAUDE_CONFIG_DIR=data/`, `CLAUDE_CODE_TMPDIR=tmp/`, `DISABLE_AUTOUPDATER=1`
8. Exec the binary, forwarding all arguments

Binary downloads come from `https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases`. The version manifest at `{bucket}/{version}/manifest.json` contains per-platform SHA256 checksums.

## Key Constraints

- Everything must stay self-contained -- never reference `~/.claude/` or system-wide paths
- Auto-updates are intentionally disabled (`DISABLE_AUTOUPDATER=1`); users update manually via `update` subcommand
- `claude.ps1` and `claude.cmd` must work without Git pre-installed (they bootstrap Portable Git)
- `claude.sh` assumes Git is already available (standard on macOS/Linux)
- `.gitattributes` enforces line endings: `.cmd` files must be CRLF, `.ps1` files must be CRLF, `.sh` files must be LF
- The `data/` and `bin/` directories are gitignored -- they contain user state and downloaded binaries
- Keep parity between `claude.ps1`, `claude.cmd`, and `claude.sh` -- all should support the same subcommands and behavior
- Use hyphens, not em dashes, in all text output
