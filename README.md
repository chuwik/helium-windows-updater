# Helium Browser Auto-Updater

[![CI](https://github.com/chuwik/helium-windows-updater/actions/workflows/ci.yml/badge.svg)](https://github.com/chuwik/helium-windows-updater/actions/workflows/ci.yml)

A PowerShell-based auto-updater for [Helium browser](https://github.com/imputnet/helium-windows) on Windows, since Helium doesn't have built-in auto-update functionality.

## Features

- ✅ Checks for updates from GitHub releases automatically
- ✅ Installs Helium browser automatically if not already installed
- ✅ Runs on Windows login and daily at noon
- ✅ Shows a message box when an update is available
- ✅ Downloads and installs updates silently (after user approval)
- ✅ Auto-detects CPU architecture (x64 or ARM64)
- ✅ Verifies installer checksum (SHA256) before installation
- ✅ Cleans up installer files after installation
- ✅ Logs activity for troubleshooting

## Installation

1. Open PowerShell
2. Navigate to this directory:
   ```powershell
   cd path\to\helium-windows-updater
   ```
3. Run the installer:
   ```powershell
   .\Install-HeliumUpdater.ps1
   ```

The installer will:
- Copy the update script to `%LOCALAPPDATA%\HeliumUpdater`
- Create two scheduled tasks:
  - **HeliumUpdater-Login**: Runs when you log in to Windows
  - **HeliumUpdater-Daily**: Runs daily at 12:00 PM
- Offer to install Helium (if not installed) or check for updates

## Usage

After installation, the updater runs automatically. You can also manually check for updates:

```powershell
& "$env:LOCALAPPDATA\HeliumUpdater\Update-Helium.ps1"
```

### When an Update is Available

1. You'll see a message box asking if you want to install the update
2. Click "Yes" to download and install the update
3. Click "No" to be reminded on the next scheduled run

**Note**: If Helium is running when you try to install, you'll be prompted to close it first.

## Uninstallation

To remove the updater (this does NOT remove Helium browser):

```powershell
cd path\to\helium-windows-updater
.\Uninstall-HeliumUpdater.ps1
```

Or manually:
1. Open Task Scheduler and delete tasks named `HeliumUpdater-Login` and `HeliumUpdater-Daily`
2. Delete the folder `%LOCALAPPDATA%\HeliumUpdater`

## Files

| File | Description |
|------|-------------|
| `Update-Helium.ps1` | Main update check script |
| `Install-HeliumUpdater.ps1` | One-time setup script |
| `Uninstall-HeliumUpdater.ps1` | Removal script |
| `build.ps1` | Build script — runs lint and tests |

After installation, files are located at:
```
%LOCALAPPDATA%\HeliumUpdater\
├── Update-Helium.ps1      # The update script
├── config.json            # Tracks installed version
└── helium-updater.log     # Debug log
```

## Configuration

The `config.json` file tracks:
- `installedHeliumVersion`: Your current Helium version (e.g., "0.7.10.1")
- `lastChecked`: When updates were last checked

You can manually edit this file if needed.

## Troubleshooting

**Check the log file:**
```powershell
Get-Content "$env:LOCALAPPDATA\HeliumUpdater\helium-updater.log" -Tail 50
```

**Verify scheduled tasks are registered:**
```powershell
Get-ScheduledTask -TaskName "HeliumUpdater*"
```

**Run the updater manually with verbose output:**
```powershell
& "$env:LOCALAPPDATA\HeliumUpdater\Update-Helium.ps1" -Verbose
```

## Requirements

- Windows 10/11
- PowerShell 5.1 or later (included with Windows)
- Internet connection (to check GitHub releases)

## Development

Run the full build (lint + tests):

```powershell
.\build.ps1
```

Run specific tasks:

```powershell
.\build.ps1 -Task Lint         # PSScriptAnalyzer only
.\build.ps1 -Task Unit         # Unit tests only
.\build.ps1 -Task Integration  # Integration tests only
.\build.ps1 -Task Test         # All tests (no lint)
```

Dependencies (Pester v5, PSScriptAnalyzer) are installed automatically on first run.

## Releasing

Releases are automated via GitHub Actions. To publish a new release:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

This creates a GitHub Release with a zip of all scripts and a SHA256 checksum file. Release notes are auto-generated from commits since the last tag.

## License

MIT License - feel free to modify and distribute.
