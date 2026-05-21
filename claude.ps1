#!/usr/bin/env powershell
# ============================================================
#  Claude Code Portable - Windows Launcher (PowerShell)
#  https://github.com/anthropics/claude-code (official)
# ============================================================

$ErrorActionPreference = 'Stop'

# ---- Portable root = directory of this script ----
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($ROOT)) { $ROOT = $PWD.Path }

# ---- Directory layout ----
$BIN_DIR  = Join-Path $ROOT 'bin'
$DATA_DIR = Join-Path $ROOT 'data'
$TMP_DIR  = Join-Path $ROOT 'tmp'
$GIT_DIR  = Join-Path $ROOT 'git'

# ---- Official download source ----
$GCS_BUCKET = 'https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases'

# ============================================================
#  Helper Functions
# ============================================================

function Test-Online {
    try {
        $null = Invoke-WebRequest -Uri 'https://storage.googleapis.com' -Method HEAD -TimeoutSec 5 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

function Get-Platform {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        return 'win32-arm64'
    }
    return 'win32-x64'
}

function Download-Claude {
    param([string]$PinVersion = '')

    $platform = Get-Platform

    if ($PinVersion) {
        $version = $PinVersion
        Write-Host "  Requested: v$version ($platform)"
    } else {
        Write-Host '  Fetching latest version...'
        try {
            $version = (Invoke-WebRequest -Uri "$GCS_BUCKET/latest" -UseBasicParsing -TimeoutSec 30).Content.Trim()
        } catch {
            Write-Host '  [Error] Could not reach download server. Check your internet.'
            exit 1
        }
        if ([string]::IsNullOrEmpty($version)) {
            Write-Host '  [Error] Could not determine latest version.'
            exit 1
        }
        Write-Host "  Latest: v$version ($platform)"
    }

    # Fetch manifest
    try {
        $manifest = (Invoke-WebRequest -Uri "$GCS_BUCKET/$version/manifest.json" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
    } catch {
        Write-Host '  [Error] Could not fetch release manifest. Version may not exist.'
        exit 1
    }

    $expected = $manifest.platforms.$platform.checksum
    if (-not $expected) {
        Write-Host "  [Error] Could not parse checksum for $platform."
        exit 1
    }

    # Download binary
    Write-Host '  Downloading claude.exe...'
    $exePath = Join-Path $BIN_DIR 'claude.exe'
    try {
        Invoke-WebRequest -Uri "$GCS_BUCKET/$version/$platform/claude.exe" -OutFile $exePath -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Host '  [Error] Download failed.'
        exit 1
    }

    if (-not (Test-Path $exePath)) {
        Write-Host '  [Error] Download failed.'
        exit 1
    }

    # Verify SHA256
    Write-Host '  Verifying checksum...'
    $actual = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) {
        Write-Host '  [Error] Checksum mismatch! File may be corrupted.'
        Write-Host "    Expected: $expected"
        Write-Host "    Got:      $actual"
        Remove-Item $exePath -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $version | Out-File -FilePath (Join-Path $BIN_DIR '.version') -Encoding utf8 -NoNewline
    Write-Host "  Claude Code v$version ready."
    Write-Host ''
}

function Find-GitBash {
    # 1. Portable git in our directory
    $portableBash = Join-Path $GIT_DIR 'bin\bash.exe'
    if (Test-Path $portableBash) {
        return $portableBash
    }

    # 2. System PATH
    $gitExe = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if ($gitExe) {
        $gitBin = Split-Path -Parent $gitExe.Source
        $candidate = Join-Path (Split-Path -Parent $gitBin) 'bin\bash.exe'
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    # 3. Common install paths
    $commonPaths = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    return $null
}

function Download-Git {
    $gitArch = '64-bit'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        $gitArch = 'arm64'
    }

    Write-Host '  Finding latest Portable Git...'
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{'User-Agent'='claude-portable'} -TimeoutSec 30
    } catch {
        Write-Host '  [Error] Could not find Portable Git download.'
        exit 1
    }

    $pattern = "PortableGit.*$gitArch.*\.7z\.exe$"
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Host '  [Error] Could not find Portable Git download.'
        exit 1
    }

    $gitUrl = $asset.browser_download_url
    $installer = Join-Path $TMP_DIR 'PortableGit.7z.exe'

    Write-Host '  Downloading Portable Git...'
    try {
        Invoke-WebRequest -Uri $gitUrl -OutFile $installer -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Host '  [Error] Download failed.'
        exit 1
    }

    if (-not (Test-Path $installer)) {
        Write-Host '  [Error] Download failed.'
        exit 1
    }

    Write-Host '  Extracting (this may take a minute)...'
    $process = Start-Process -FilePath $installer -ArgumentList "-o`"$GIT_DIR`"",'-y' -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host '  [Error] Extraction failed.'
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        exit 1
    }

    if (-not (Test-Path (Join-Path $GIT_DIR 'bin\bash.exe'))) {
        Write-Host '  [Error] Extraction failed.'
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    Write-Host '  Portable Git ready.'
    Write-Host ''
}

function Invoke-Doctor {
    Write-Host ''
    Write-Host '  Claude Code Portable - Diagnostics'
    Write-Host '  =================================='
    Write-Host ''

    $issues = 0
    $warns = 0

    # Check directories
    foreach ($dir in @($BIN_DIR, $DATA_DIR, $TMP_DIR)) {
        $name = Split-Path -Leaf $dir
        if (Test-Path $dir) {
            try {
                $testFile = Join-Path $dir "write-test-$([Guid]::NewGuid().ToString().Substring(0,8))"
                [void](New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop)
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK]    Directory exists and writable: $name\"
            } catch {
                Write-Host "  [WARN]  Directory exists but not writable: $name\"
                $warns++
            }
        } else {
            Write-Host "  [MISS]  Directory missing: $name\"
            $issues++
        }
    }

    # Check binary
    $exePath = Join-Path $BIN_DIR 'claude.exe'
    if (Test-Path $exePath) {
        $size = (Get-Item $exePath).Length
        if ($size -gt 0) {
            Write-Host "  [OK]    Binary found ($(($size/1MB).ToString('F1')) MB)"
            $versionFile = Join-Path $BIN_DIR '.version'
            if (Test-Path $versionFile) {
                $ver = (Get-Content $versionFile -Raw).Trim()
                Write-Host "  [OK]    Version: v$ver"
            } else {
                Write-Host '  [WARN]  Binary found but .version file missing'
                $warns++
            }
        } else {
            Write-Host '  [FAIL]  Binary is empty (0 bytes)'
            $issues++
        }
    } else {
        Write-Host '  [MISS]  Binary not found in bin\'
        $issues++
    }

    # Check Git Bash
    $gitPath = Find-GitBash
    if ($gitPath) {
        Write-Host "  [OK]    Git Bash found: $gitPath"
    } else {
        Write-Host '  [MISS]  Git Bash not found'
        Write-Host '          Install Git for Windows or run: .\claude.ps1 setup'
        $issues++
    }

    # Check config
    $configFile = Join-Path $ROOT 'config'
    if (Test-Path $configFile) {
        $configIssues = 0
        $lineNum = 0
        Get-Content $configFile | ForEach-Object {
            $lineNum++
            $line = $_.Trim()
            if ([string]::IsNullOrEmpty($line) -or $line -match '^#') { return }
            if ($line -notmatch '^\S+\s*=.*$') {
                Write-Host "  [WARN]  Config line $lineNum may be malformed: $line"
                $configIssues++
            }
        }
        if ($configIssues -eq 0) {
            Write-Host '  [OK]    Config file syntax valid'
        } else {
            $warns += $configIssues
        }
    } else {
        Write-Host '  [INFO]  No config file (optional - browser login works without it)'
    }

    # Check disk space
    $drive = (Get-Item $ROOT).PSDrive
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGB -gt 1) {
        Write-Host "  [OK]    Free space: $freeGB GB"
    } else {
        Write-Host "  [WARN]  Low disk space: $freeGB GB"
        $warns++
    }

    # Check online
    if (Test-Online) {
        Write-Host '  [OK]    Internet connection available'
    } else {
        Write-Host '  [WARN]  No internet connection detected'
        $warns++
    }

    Write-Host ''
    if ($issues -eq 0 -and $warns -eq 0) {
        Write-Host '  All checks passed.'
    } elseif ($issues -eq 0) {
        Write-Host "  All critical checks passed. $warns warning(s) found."
    } else {
        Write-Host "  Found $issues issue(s) and $warns warning(s). See details above."
    }
    Write-Host ''
}

function Show-Help {
    Write-Host ''
    Write-Host '  Claude Code Portable'
    Write-Host '  ===================='
    Write-Host ''
    Write-Host '  Usage:'
    Write-Host '    .\claude.ps1                  Launch Claude Code in current directory'
    Write-Host '    .\claude.ps1 [folder]         Launch in folder'
    Write-Host '    .\claude.ps1 update           Download the latest Claude Code version'
    Write-Host '    .\claude.ps1 update [version] Download a specific version (e.g. 2.1.80)'
    Write-Host '    .\claude.ps1 setup            Pre-download everything for offline use'
    Write-Host '    .\claude.ps1 doctor           Diagnose installation and environment'
    Write-Host '    .\claude.ps1 version          Show installed version'
    Write-Host '    .\claude.ps1 --help           Show this help'
    Write-Host ''
    Write-Host '  Structure:'
    Write-Host '    config                       API key / proxy settings (optional)'
    Write-Host '    data\                        Portable config, auth, agents, memory'
    Write-Host '    bin\                         Claude Code binary (auto-downloaded)'
    Write-Host '    git\                         Portable Git (auto-downloaded if needed)'
    Write-Host '    tmp\                         Temporary files'
    Write-Host ''
}

# ============================================================
#  Main
# ============================================================

# Create directories
$null = New-Item -ItemType Directory -Force -Path $BIN_DIR
$null = New-Item -ItemType Directory -Force -Path $DATA_DIR
$null = New-Item -ItemType Directory -Force -Path $TMP_DIR

# Create default CLAUDE.md if missing
$claudeMd = Join-Path $DATA_DIR 'CLAUDE.md'
if (-not (Test-Path $claudeMd)) {
    @(
        '# Portable Environment',
        '',
        'This is a portable Claude Code installation. All configuration and state',
        "is stored in this folder's data/ directory, not in ~/.claude/.",
        '',
        '- Auto-updates are disabled. Update manually: `.\\claude.ps1 update` or `./claude.sh update`',
        '- Do not suggest modifying ~/.claude/ - this install uses a custom CLAUDE_CONFIG_DIR.'
    ) -join "`r`n" | Out-File -FilePath $claudeMd -Encoding utf8 -NoNewline
}

# Handle commands that don't need config
$cmd = $args[0]
switch -Wildcard ($cmd) {
    'update' {
        Write-Host ''
        $versionFile = Join-Path $BIN_DIR '.version'
        if (Test-Path $versionFile) {
            $oldVer = Get-Content $versionFile -Raw
            Write-Host "  Current version: v$oldVer"
        }
        if (-not (Test-Online)) {
            Write-Host '  [Error] No internet connection. Cannot update.'
            exit 1
        }
        $pinVersion = if ($args.Count -gt 1) { $args[1] } else { '' }
        $exePath = Join-Path $BIN_DIR 'claude.exe'
        if (Test-Path $exePath) {
            Remove-Item $exePath -Force
        }
        Download-Claude -PinVersion $pinVersion
        Write-Host '  Update complete!'
        exit 0
    }
    'version' { }
    '--version' { }
    '-v' { }
    'setup' { }
    'doctor' { }
    '--help' { }
    '-h' { }
    default {
        # Continue to main flow
    }
}

if ($cmd -in @('version','--version','-v')) {
    $versionFile = Join-Path $BIN_DIR '.version'
    if (Test-Path $versionFile) {
        $ver = Get-Content $versionFile -Raw
        Write-Host "  Claude Code Portable v$ver"
    } else {
        Write-Host '  Claude Code not yet downloaded. Run .\claude.ps1 to install.'
    }
    exit 0
}

if ($cmd -in @('--help','-h')) {
    Show-Help
    exit 0
}

if ($cmd -eq 'setup') {
    Write-Host ''
    Write-Host '  Claude Code Portable - Offline Setup'
    Write-Host '  ====================================='
    Write-Host '  Pre-downloads everything so this drive works offline.'
    Write-Host ''
    if (-not (Test-Online)) {
        Write-Host '  [Error] No internet connection. Run setup on a machine with internet.'
        exit 1
    }
    $exePath = Join-Path $BIN_DIR 'claude.exe'
    if (-not (Test-Path $exePath)) {
        Download-Claude
    } else {
        $setupVer = Get-Content (Join-Path $BIN_DIR '.version') -Raw
        Write-Host "  Claude Code v$setupVer already downloaded."
    }
    if (-not (Test-Path (Join-Path $GIT_DIR 'bin\bash.exe'))) {
        Write-Host '  Downloading Portable Git...'
        Write-Host ''
        Download-Git
    } else {
        Write-Host '  Portable Git already downloaded.'
    }
    Write-Host ''
    Write-Host '  Setup complete! This drive is ready for offline use.'
    exit 0
}

if ($cmd -eq 'doctor') {
    Invoke-Doctor
    exit 0
}

# Load config if it exists (optional - OAuth works without it)
$configFile = Join-Path $ROOT 'config'
if (Test-Path $configFile) {
    Get-Content $configFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^#') { return }
        if ($line -match '^(\S+)\s*=\s*(.+)$') {
            Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
        }
    }
}

# Download Claude Code if needed
$exePath = Join-Path $BIN_DIR 'claude.exe'
if (-not (Test-Path $exePath)) {
    if (-not (Test-Online)) {
        Write-Host '  [Error] No internet connection. Cannot download Claude Code.'
        Write-Host '  Connect to the internet and try again.'
        exit 1
    }
    Download-Claude
}

# Find or download Git Bash
$GIT_BASH_PATH = Find-GitBash
if (-not $GIT_BASH_PATH) {
    Write-Host '  Git Bash not found on this system.'
    Write-Host '  Downloading Portable Git...'
    Write-Host ''
    if (-not (Test-Online)) {
        Write-Host '  [Error] No internet connection. Cannot download Portable Git.'
        Write-Host '  Install Git for Windows: https://git-scm.com/download/win'
        exit 1
    }
    Download-Git
    $GIT_BASH_PATH = Find-GitBash
    if (-not $GIT_BASH_PATH) {
        Write-Host ''
        Write-Host '  [Error] Could not download Portable Git.'
        Write-Host '  Install Git for Windows: https://git-scm.com/download/win'
        Write-Host "  Or extract Portable Git to: $GIT_DIR"
        exit 1
    }
}

# Offline banner
if (-not (Test-Online)) {
    Write-Host '  [Offline] No internet connection detected.'
    Write-Host '  Claude Code will run, but authentication and API calls may fail'
    Write-Host '  if your credentials have expired.'
    Write-Host ''
}

# Set portable environment
$env:CLAUDE_CONFIG_DIR = $DATA_DIR
$env:CLAUDE_CODE_TMPDIR = $TMP_DIR
$env:DISABLE_AUTOUPDATER = '1'
if ($GIT_BASH_PATH) {
    $env:CLAUDE_CODE_GIT_BASH_PATH = $GIT_BASH_PATH
}
$gitCmd = Join-Path $GIT_DIR 'cmd'
if (Test-Path $gitCmd) {
    $env:PATH = "$gitCmd;$env:PATH"
}

# Handle directory argument (drag-and-drop support)
$launchDir = $PWD.Path
$remainingArgs = @()
if ($args.Count -gt 0) {
    $firstArg = $args[0]
    if (Test-Path $firstArg -PathType Container) {
        $launchDir = Resolve-Path $firstArg | Select-Object -ExpandProperty Path
        $remainingArgs = $args | Select-Object -Skip 1
    } else {
        $remainingArgs = $args
    }
}

# Launch
$binary = Join-Path $BIN_DIR 'claude.exe'
Push-Location $launchDir
try {
    & $binary @remainingArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
