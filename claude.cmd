@echo off
:: ---- Try PowerShell first; fallback to CMD below ----
set "_PS1=%~dp0claude.ps1"
if exist "%_PS1%" (
    where pwsh.exe >nul 2>&1 && (
        pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%_PS1%" %*
        exit /b %errorlevel%
    )
    where powershell.exe >nul 2>&1 && (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%_PS1%" %*
        exit /b %errorlevel%
    )
)
setlocal enabledelayedexpansion

:: ============================================================
::  Claude Code Portable - Windows Launcher (CMD Fallback)
::  https://github.com/anthropics/claude-code (official)
:: ============================================================

title Claude Code Portable

:: ---- Portable root = directory of this script ----
set "ROOT=%~dp0"
if "!ROOT:~-1!"=="\" set "ROOT=!ROOT:~0,-1!"

:: ---- Directory layout ----
set "BIN_DIR=!ROOT!\bin"
set "DATA_DIR=!ROOT!\data"
set "TMP_DIR=!ROOT!\tmp"
set "GIT_DIR=!ROOT!\git"

:: ---- Official download source ----
set "GCS_BUCKET=https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

:: ---- Create directories ----
if not exist "!BIN_DIR!" mkdir "!BIN_DIR!"
if not exist "!DATA_DIR!" mkdir "!DATA_DIR!"
if not exist "!TMP_DIR!" mkdir "!TMP_DIR!"

:: ---- Create default CLAUDE.md if missing ----
if not exist "!DATA_DIR!\CLAUDE.md" (
    (
        echo # Portable Environment
        echo.
        echo This is a portable Claude Code installation. All configuration and state
        echo is stored in this folder's data/ directory, not in ~/.claude/.
        echo.
        echo - Auto-updates are disabled. Update manually: `.\claude.ps1 update` or `./claude.sh update`
        echo - Do not suggest modifying ~/.claude/ - this install uses a custom CLAUDE_CONFIG_DIR.
    ) > "!DATA_DIR!\CLAUDE.md"
)

:: ---- Handle commands that don't need config ----
if /i "%~1"=="update" goto :cmd_update
if /i "%~1"=="version" goto :cmd_version
if /i "%~1"=="--version" goto :cmd_version
if /i "%~1"=="-v" goto :cmd_version
if /i "%~1"=="setup" goto :cmd_setup
if /i "%~1"=="--help" goto :cmd_help
if /i "%~1"=="-h" goto :cmd_help

:: ---- Load config if it exists (optional - OAuth works without it) ----
if exist "!ROOT!\config" (
    for /f "usebackq eol=# tokens=1,* delims==" %%a in ("!ROOT!\config") do (
        if not "%%b"=="" set "%%a=%%b"
    )
)

:: ---- Download Claude Code if needed ----
if not exist "!BIN_DIR!\claude.exe" (
    call :check_online
    if errorlevel 1 (
        echo   [Error] No internet connection. Cannot download Claude Code.
        echo   Connect to the internet and try again.
        pause
        exit /b 1
    )
    call :download_claude
    if errorlevel 1 (
        echo   [Error] Failed to download Claude Code.
        pause
        exit /b 1
    )
)

:: ---- Find or download Git Bash ----
set "GIT_BASH_PATH="
call :find_git_bash
if not defined GIT_BASH_PATH (
    echo   Git Bash not found on this system.
    echo   Downloading Portable Git...
    echo.
    call :check_online
    if errorlevel 1 (
        echo   [Error] No internet connection. Cannot download Portable Git.
        echo   Install Git for Windows: https://git-scm.com/download/win
        pause
        exit /b 1
    )
    call :download_git
    if errorlevel 1 (
        echo.
        echo   [Error] Could not download Portable Git.
        echo   Install Git for Windows: https://git-scm.com/download/win
        echo   Or extract Portable Git to: !GIT_DIR!
        pause
        exit /b 1
    )
    call :find_git_bash
)

:: ---- Offline banner ----
call :check_online
if errorlevel 1 (
    echo   [Offline] No internet connection detected.
    echo   Claude Code will run, but authentication and API calls may fail
    echo   if your credentials have expired.
    echo.
)

:: ---- Set portable environment ----
set "CLAUDE_CONFIG_DIR=!DATA_DIR!"
set "CLAUDE_CODE_TMPDIR=!TMP_DIR!"
set "DISABLE_AUTOUPDATER=1"
if defined GIT_BASH_PATH set "CLAUDE_CODE_GIT_BASH_PATH=!GIT_BASH_PATH!"
if exist "!GIT_DIR!\cmd" set "PATH=!GIT_DIR!\cmd;!PATH!"

:: ---- Launch ----
:: If first arg is a directory, cd there and launch (drag-and-drop support)
if "%~1" neq "" (
    pushd "%~1" 2>nul && (
        "!BIN_DIR!\claude.exe"
        popd
        exit /b !errorlevel!
    )
)
"!BIN_DIR!\claude.exe" %*
exit /b !errorlevel!


:: ============================================================
::  Functions
:: ============================================================

:check_online
:: Any HTTP response (even 400) means we're online. Only connection failures mean offline.
curl.exe -sS --head --connect-timeout 5 "https://storage.googleapis.com" >nul 2>&1
exit /b !errorlevel!


:download_claude
set "PLATFORM=win32-x64"
if /i "!PROCESSOR_ARCHITECTURE!"=="ARM64" set "PLATFORM=win32-arm64"

:: Use pinned version or fetch latest
if defined PIN_VERSION (
    set "VERSION=!PIN_VERSION!"
    echo   Requested: v!VERSION! ^(!PLATFORM!^)
) else (
    echo   Fetching latest version...
    for /f "usebackq delims=" %%v in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; (Invoke-WebRequest -Uri '!GCS_BUCKET!/latest' -UseBasicParsing).Content.Trim()"`) do set "VERSION=%%v"
    if not defined VERSION (
        echo   [Error] Could not reach download server. Check your internet.
        exit /b 1
    )
    echo   Latest: v!VERSION! ^(!PLATFORM!^)
)

for /f "usebackq delims=" %%c in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $m=(Invoke-WebRequest -Uri '!GCS_BUCKET!/!VERSION!/manifest.json' -UseBasicParsing).Content | ConvertFrom-Json; $m.platforms.'!PLATFORM!'.checksum"`) do set "EXPECTED=%%c"
if not defined EXPECTED (
    echo   [Error] Could not fetch release manifest. Version may not exist.
    exit /b 1
)

echo   Downloading claude.exe...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '!GCS_BUCKET!/!VERSION!/!PLATFORM!/claude.exe' -OutFile '!BIN_DIR!\claude.exe' -UseBasicParsing"
if not exist "!BIN_DIR!\claude.exe" (
    echo   [Error] Download failed.
    exit /b 1
)

echo   Verifying checksum...
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "!BIN_DIR!\claude.exe" SHA256') do (
    if not defined ACTUAL set "ACTUAL=%%h"
)
:: Strip spaces (some certutil versions add them)
set "ACTUAL=!ACTUAL: =!"
if /i "!ACTUAL!" neq "!EXPECTED!" (
    echo   [Error] Checksum mismatch! File may be corrupted.
    echo     Expected: !EXPECTED!
    echo     Got:      !ACTUAL!
    del "!BIN_DIR!\claude.exe" >nul 2>&1
    exit /b 1
)

echo !VERSION!> "!BIN_DIR!\.version"
echo   Claude Code v!VERSION! ready.
echo.
exit /b 0


:cmd_update
echo.
if exist "!BIN_DIR!\.version" (
    set /p OLD_VER=<"!BIN_DIR!\.version"
    echo   Current version: v!OLD_VER!
)
call :check_online
if errorlevel 1 (
    echo   [Error] No internet connection. Cannot update.
    pause
    exit /b 1
)
:: Support pinned version: claude.cmd update 2.1.80
if "%~2" neq "" set "PIN_VERSION=%~2"
if exist "!BIN_DIR!\claude.exe" del "!BIN_DIR!\claude.exe"
call :download_claude
if errorlevel 1 (
    echo   Update failed.
    pause
    exit /b 1
)
echo   Update complete!
pause
exit /b 0


:cmd_version
if exist "!BIN_DIR!\.version" (
    set /p VER=<"!BIN_DIR!\.version"
    echo   Claude Code Portable v!VER!
) else (
    echo   Claude Code not yet downloaded. Run claude.cmd to install.
)
exit /b 0


:find_git_bash
:: 1. Portable git in our directory
if exist "!GIT_DIR!\bin\bash.exe" (
    set "GIT_BASH_PATH=!GIT_DIR!\bin\bash.exe"
    exit /b 0
)
:: 2. System PATH
where git.exe >nul 2>&1
if !errorlevel! equ 0 (
    for /f "delims=" %%g in ('where git.exe 2^>nul') do (
        set "_gdir=%%~dpg"
        set "_gdir=!_gdir:~0,-1!"
        for %%d in ("!_gdir!") do set "_parent=%%~dpd"
        if exist "!_parent!bin\bash.exe" (
            set "GIT_BASH_PATH=!_parent!bin\bash.exe"
            exit /b 0
        )
    )
)
:: 3. Common install paths
for %%p in (
    "C:\Program Files\Git\bin\bash.exe"
    "C:\Program Files (x86)\Git\bin\bash.exe"
) do (
    if exist %%p (
        set "GIT_BASH_PATH=%%~p"
        exit /b 0
    )
)
exit /b 1


:download_git
set "GIT_ARCH=64-bit"
if /i "!PROCESSOR_ARCHITECTURE!"=="ARM64" set "GIT_ARCH=arm64"

echo   Finding latest Portable Git...
for /f "usebackq delims=" %%u in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $r=Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{'User-Agent'='claude-portable'}; ($r.assets | Where-Object { $_.name -match 'PortableGit.*!GIT_ARCH!.*\.7z\.exe$' } | Select-Object -First 1).browser_download_url"`) do set "GIT_URL=%%u"
if not defined GIT_URL (
    echo   [Error] Could not find Portable Git download.
    exit /b 1
)

echo   Downloading Portable Git...
set "GIT_INSTALLER=!TMP_DIR!\PortableGit.7z.exe"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '!GIT_URL!' -OutFile '!GIT_INSTALLER!' -UseBasicParsing"
if not exist "!GIT_INSTALLER!" (
    echo   [Error] Download failed.
    exit /b 1
)

echo   Extracting (this may take a minute)...
"!GIT_INSTALLER!" -o"!GIT_DIR!" -y >nul 2>&1
if not exist "!GIT_DIR!\bin\bash.exe" (
    echo   [Error] Extraction failed.
    del "!GIT_INSTALLER!" >nul 2>&1
    exit /b 1
)
del "!GIT_INSTALLER!" >nul 2>&1
echo   Portable Git ready.
echo.
exit /b 0


:cmd_setup
echo.
echo   Claude Code Portable - Offline Setup
echo   =====================================
echo   Pre-downloads everything so this drive works offline.
echo.
call :check_online
if errorlevel 1 (
    echo   [Error] No internet connection. Run setup on a machine with internet.
    pause
    exit /b 1
)
:: Download Claude Code if needed
if not exist "!BIN_DIR!\claude.exe" (
    call :download_claude
    if errorlevel 1 (
        echo   [Error] Failed to download Claude Code.
        pause
        exit /b 1
    )
) else (
    set /p SETUP_VER=<"!BIN_DIR!\.version"
    echo   Claude Code v!SETUP_VER! already downloaded.
)
:: Always download Portable Git (even if this machine has system Git)
if not exist "!GIT_DIR!\bin\bash.exe" (
    echo   Downloading Portable Git...
    echo.
    call :download_git
    if errorlevel 1 (
        echo   [Error] Failed to download Portable Git.
        pause
        exit /b 1
    )
) else (
    echo   Portable Git already downloaded.
)
echo.
echo   Setup complete! This drive is ready for offline use.
pause
exit /b 0


:cmd_help
echo.
echo   Claude Code Portable
echo   ====================
echo.
echo   Usage:
echo     claude.cmd                  Launch Claude Code in current directory
echo     claude.cmd [folder]         Launch in folder (drag-and-drop supported)
echo     claude.cmd update           Download the latest Claude Code version
echo     claude.cmd update [version] Download a specific version (e.g. 2.1.80)
echo     claude.cmd setup            Pre-download everything for offline use
echo     claude.cmd version          Show installed version
echo     claude.cmd --help           Show this help
echo.
echo   Structure:
echo     config                      API key / proxy settings (optional)
echo     data\                       Portable config, auth, agents, memory
echo     bin\                        Claude Code binary (auto-downloaded)
echo     git\                        Portable Git (auto-downloaded if needed)
echo     tmp\                        Temporary files
echo.
exit /b 0
