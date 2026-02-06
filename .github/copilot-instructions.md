# Copilot Instructions

## Project Overview

PowerShell-based auto-updater for [Helium browser](https://github.com/imputnet/helium-windows) on Windows. It polls GitHub releases for new versions, notifies the user, and performs silent installation. There is no build system, test suite, or linter — changes are validated manually.

## Architecture

Three standalone PowerShell scripts, each with a specific role:

- **`Update-Helium.ps1`** — Core updater logic. Runs as a scheduled task (on login + daily at noon). Checks GitHub API for the latest release, compares versions, prompts the user, downloads and installs the update. Also handles direct install invocation via `-Install -Version` parameters (triggered from toast notification buttons).
- **`Install-HeliumUpdater.ps1`** — One-time setup. Copies `Update-Helium.ps1` to `%LOCALAPPDATA%\HeliumUpdater\`, registers two Windows Scheduled Tasks, creates `config.json`, and cleans up legacy protocol handlers.
- **`Uninstall-HeliumUpdater.ps1`** — Tears down scheduled tasks, protocol handler registry key, and the `%LOCALAPPDATA%\HeliumUpdater\` directory.

### Runtime file layout (after installation)

```
%LOCALAPPDATA%\HeliumUpdater\
├── Update-Helium.ps1      # Copied from repo
├── config.json            # Tracks installedHeliumVersion + lastChecked
└── helium-updater.log     # Append-only log
```

## Releases

Tag-triggered GitHub Actions workflow (`.github/workflows/release.yml`). Pushing a `v*` tag builds a zip of the scripts, generates a SHA256 checksum, and creates a GitHub Release with auto-generated notes. The zip includes `Update-Helium.ps1`, `Install-HeliumUpdater.ps1`, `Uninstall-HeliumUpdater.ps1`, `README.md`, and `LICENSE`.

## Key Conventions

- **PowerShell 5.1 minimum** — All scripts use `#Requires -Version 5.1`. Do not use PowerShell 7+ features (e.g., ternary operator, `&&` chaining, null-coalescing).
- **Script-scoped variables** — Configuration constants use `$script:` scope prefix (e.g., `$script:AppDataPath`, `$script:GitHubApiUrl`).
- **Write-Log pattern** — `Update-Helium.ps1` uses a `Write-Log` function that writes timestamped `[$Level]` entries to the log file and routes errors through `Write-Error` / verbose through `Write-Verbose`. The install/uninstall scripts use a simpler `Write-Status` function with colored console output.
- **Version format** — Versions follow `MAJOR.MINOR.PATCH[.BUILD]` (e.g., `0.7.10.1`). The `$script:VersionPattern` regex validates this. Versions are compared segment-by-segment after stripping `v` prefix and pre-release suffixes.
- **Concurrency control** — A file-based lock (`updater.lock` with PID) prevents concurrent updater executions, with a 10-minute stale lock timeout.
- **Security checks** — Installer downloads are verified via SHA256 checksum from the GitHub API asset digest. Version strings are validated against `$script:VersionPattern` before use in file paths to prevent injection.
- **Notification fallback** — Uses BurntToast module for toast notifications if available; falls back to `System.Windows.Forms.MessageBox`.
- **Error handling** — Install/uninstall scripts set `$ErrorActionPreference = "Stop"`. The updater uses try/catch blocks with `Write-Log` for error reporting and always releases the lock in a `finally` block.
