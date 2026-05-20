# Claude Code Portable

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) from a USB drive or any folder - no installation required. Works on Windows, macOS, and Linux.

## Quick Start

1. **Download** this repo (or grab the [latest release](../../releases))
2. **Run the launcher:**
   - **Windows (PowerShell):** `powershell -ExecutionPolicy Bypass -File claude.ps1`
   - **Windows (fallback):** Double-click `claude.cmd`
   - **macOS/Linux:** Run `./claude.sh`
3. **First run** downloads the Claude Code binary and (on Windows) Portable Git automatically
4. **Log in** when Claude Code opens your browser, or use an API key via the `config` file

That's it. Everything lives in this folder.

## How It Works

The launcher scripts download the official Claude Code binary from Anthropic's servers, then configure it to store all state locally:

| What | Where | Purpose |
|------|-------|---------|
| `bin/` | Auto-created | Claude Code binary |
| `data/` | Auto-created | Config, credentials, agents, rules, memory |
| `tmp/` | Auto-created | Temporary files |
| `git/` | Auto-created (Windows) | Portable Git (if not installed on system) |
| `config` | You create (optional) | API key, proxy URL - see `config.example` |
| `claude.ps1` | Included | Primary Windows launcher (PowerShell) |
| `claude.cmd` | Included | Windows fallback when PowerShell is unavailable |

**Nothing is written outside this folder.** Plug the drive into another machine and pick up where you left off.

## Authentication

**Option A - Claude account (easiest):** Just run the launcher. Claude Code opens your browser to log in. Credentials are stored in `data/` on the drive.

**Option B - API key:** Copy `config.example` to `config` and add your key:
```
ANTHROPIC_API_KEY=sk-ant-...
```

**Option C - Proxy / gateway:** Set a custom base URL in the config:
```
ANTHROPIC_API_KEY=your-key
ANTHROPIC_BASE_URL=https://your-proxy.example.com
```

## Commands

```bash
# Launch Claude Code
.\claude.ps1                  # Windows (PowerShell)
claude.cmd                    # Windows (CMD fallback)
./claude.sh                   # macOS/Linux

# Launch in a specific folder
.\claude.ps1 C:\myproject     # Windows (or drag-and-drop a folder)
claude.cmd C:\myproject       # Windows fallback
./claude.sh ~/myproject       # macOS/Linux

# Update to the latest version
.\claude.ps1 update
claude.cmd update
./claude.sh update

# Pin a specific version
.\claude.ps1 update 2.1.80
claude.cmd update 2.1.80
./claude.sh update 2.1.80

# Check installed version
.\claude.ps1 version
claude.cmd version
./claude.sh version
```

Auto-updates are disabled by design. The binary stays exactly where you put it until you run `update`.

## Windows Launchers

On Windows, **PowerShell is preferred** and CMD is used only as a fallback:

- **`claude.ps1`** -- Primary launcher. Supports full error handling, native JSON parsing, and faster downloads.
- **`claude.cmd`** -- Fallback launcher. Automatically detects if `claude.ps1` and PowerShell are available and forwards to them. If PowerShell is unavailable, it runs the full CMD implementation.

Both launchers support the same commands and behavior.

## What Gets Downloaded

On first run, the launcher downloads from official sources:

- **Claude Code** (~200MB) from Anthropic's distribution server, verified with SHA256 checksums
- **Portable Git** (~60MB, Windows only) from [git-for-windows](https://github.com/git-for-windows/git) if Git isn't already installed

On macOS/Linux, Git is typically pre-installed so no extra download is needed.

## Requirements

- **Windows 10 1809+**, **macOS 13+**, or **Linux** (Ubuntu 20.04+, Debian 10+, Alpine 3.19+)
- Internet connection (for initial download and API calls)
- 4GB+ RAM

## Legal

This project contains only launcher scripts (MIT licensed). **Claude Code itself is Anthropic's proprietary software**, downloaded directly from their official servers at runtime. Use of Claude Code is subject to [Anthropic's Terms of Service](https://www.anthropic.com/legal/consumer-terms). Portable Git is distributed under the [GPL v2 license](https://github.com/git-for-windows/git/blob/main/COPYING).
