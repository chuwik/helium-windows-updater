# Helium Browser Auto-Updater

A PowerShell-based auto-updater for [Helium browser](https://github.com/imputnet/helium-windows) on Windows, since Helium doesn't have built-in auto-update functionality.

## Features

- ✅ Checks for updates from GitHub releases automatically
- ✅ Runs on Windows login and daily at noon
- ✅ Shows toast notification (or message box) when update is available
- ✅ Downloads and installs updates silently (after user approval)
- ✅ Auto-detects CPU architecture (x64 or ARM64)
- ✅ Verifies installer checksum (SHA256) before installation
- ✅ Cleans up installer files after installation
- ✅ Logs activity for troubleshooting

## Installation

1. Open PowerShell
2. Navigate to this directory:
   ```powershell
   cd D:\helium-updater
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
- Register a protocol handler for toast notification buttons
- Ask for your current Helium version (optional)

## Usage

After installation, the updater runs automatically. You can also manually check for updates:

```powershell
& "$env:LOCALAPPDATA\HeliumUpdater\Update-Helium.ps1"
```

### When an Update is Available

1. You'll see a notification asking if you want to install
2. Click "Install Now" to download and install the update
3. Click "Not Now" to be reminded on the next scheduled run

**Note**: If Helium is running when you try to install, you'll be prompted to close it first.

## Uninstallation

To remove the updater (this does NOT remove Helium browser):

```powershell
cd D:\helium-updater
.\Uninstall-HeliumUpdater.ps1
```

Or manually:
1. Open Task Scheduler and delete tasks named `HeliumUpdater-Login` and `HeliumUpdater-Daily`
2. Delete the folder `%LOCALAPPDATA%\HeliumUpdater`
3. Delete the registry key `HKCU:\Software\Classes\helium-update`

## Files

| File | Description |
|------|-------------|
| `Update-Helium.ps1` | Main update check script |
| `Install-HeliumUpdater.ps1` | One-time setup script |
| `Uninstall-HeliumUpdater.ps1` | Removal script |

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

## Optional: BurntToast Module

For nicer toast notifications with action buttons, install the BurntToast PowerShell module:

```powershell
Install-Module -Name BurntToast -Scope CurrentUser
```

Without BurntToast, the updater falls back to a standard Windows message box.

## License

MIT License - feel free to modify and distribute.
