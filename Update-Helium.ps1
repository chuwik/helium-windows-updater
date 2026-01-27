<#
.SYNOPSIS
    Helium Browser Auto-Updater
.DESCRIPTION
    Checks for updates to Helium browser from GitHub releases and prompts
    the user to install if a newer version is available.
#>

#Requires -Version 5.1

param(
    [switch]$Install,  # Called when user clicks "Install Now" from toast
    [string]$Version   # Version to install (used with -Install)
)

# Configuration
$script:GitHubApiUrl = "https://api.github.com/repos/imputnet/helium-windows/releases/latest"
$script:AppDataPath = Join-Path $env:LOCALAPPDATA "HeliumUpdater"
$script:ConfigPath = Join-Path $script:AppDataPath "config.json"
$script:LogPath = Join-Path $script:AppDataPath "helium-updater.log"
$script:LockPath = Join-Path $script:AppDataPath "updater.lock"
$script:VersionPattern = '^\d+\.\d+\.\d+(\.\d+)?$'

# Ensure app data directory exists
if (-not (Test-Path $script:AppDataPath)) {
    New-Item -ItemType Directory -Path $script:AppDataPath -Force | Out-Null
}

# Mutex to prevent concurrent executions
function Get-UpdaterLock {
    $lockTimeout = 300  # 5 minutes max wait
    $waited = 0
    
    while (Test-Path $script:LockPath) {
        # Check if lock is stale (older than 10 minutes)
        $lockAge = (Get-Date) - (Get-Item $script:LockPath).LastWriteTime
        if ($lockAge.TotalMinutes -gt 10) {
            Write-Log "Removing stale lock file"
            Remove-Item $script:LockPath -Force -ErrorAction SilentlyContinue
            break
        }
        
        if ($waited -ge $lockTimeout) {
            Write-Log "Timeout waiting for lock - another instance may be running" -Level "ERROR"
            return $false
        }
        
        Start-Sleep -Seconds 5
        $waited += 5
    }
    
    # Create lock file with current PID
    $PID | Set-Content $script:LockPath -Force
    return $true
}

function Release-UpdaterLock {
    if (Test-Path $script:LockPath) {
        Remove-Item $script:LockPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction SilentlyContinue
    if ($Level -eq "ERROR") {
        Write-Error $Message
    } else {
        Write-Verbose $Message
    }
}

function Get-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            return Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        } catch {
            Write-Log "Failed to read config: $_" -Level "ERROR"
        }
    }
    return @{
        lastChecked = $null
        installedHeliumVersion = $null
    }
}

function Save-Config {
    param($Config)
    try {
        $Config | ConvertTo-Json | Set-Content $script:ConfigPath -Force
        Write-Log "Config saved"
    } catch {
        Write-Log "Failed to save config: $_" -Level "ERROR"
    }
}

function Get-LatestRelease {
    Write-Log "Checking GitHub for latest release..."
    try {
        $response = Invoke-RestMethod -Uri $script:GitHubApiUrl -UseBasicParsing -TimeoutSec 30
        $version = $response.tag_name
        $assets = $response.assets
        
        Write-Log "Latest version: $version"
        return @{
            Version = $version
            Assets = $assets
            ReleaseUrl = $response.html_url
        }
    } catch {
        Write-Log "Failed to fetch latest release: $_" -Level "ERROR"
        return $null
    }
}

function Get-InstalledVersion {
    $config = Get-Config
    return $config.installedHeliumVersion
}

function Compare-Versions {
    param([string]$Current, [string]$Latest)
    
    if ([string]::IsNullOrEmpty($Current)) {
        return $true  # No version recorded, assume update needed
    }
    
    try {
        # Normalize versions: strip common prefixes/suffixes
        $currentClean = $Current -replace '^v', '' -replace '-.*$', ''
        $latestClean = $Latest -replace '^v', '' -replace '-.*$', ''
        
        # Validate format
        if ($currentClean -notmatch '^\d+(\.\d+)*$' -or $latestClean -notmatch '^\d+(\.\d+)*$') {
            Write-Log "Version format invalid: current='$currentClean', latest='$latestClean'" -Level "WARN"
            return $true  # Assume update needed if format is unexpected
        }
        
        # Parse versions like "0.7.10.1"
        $currentParts = $currentClean.Split('.') | ForEach-Object { [int]$_ }
        $latestParts = $latestClean.Split('.') | ForEach-Object { [int]$_ }
        
        # Pad arrays to same length
        $maxLength = [Math]::Max($currentParts.Length, $latestParts.Length)
        while ($currentParts.Length -lt $maxLength) { $currentParts += 0 }
        while ($latestParts.Length -lt $maxLength) { $latestParts += 0 }
        
        for ($i = 0; $i -lt $maxLength; $i++) {
            if ($latestParts[$i] -gt $currentParts[$i]) { return $true }
            if ($latestParts[$i] -lt $currentParts[$i]) { return $false }
        }
        return $false  # Versions are equal
    } catch {
        Write-Log "Version comparison failed: $_" -Level "ERROR"
        return $true  # Assume update needed on error (safer than missing updates)
    }
}

function Get-Architecture {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq "ARM64") {
        return "arm64"
    }
    return "x64"
}

function Get-InstallerAsset {
    param($Assets, [string]$Architecture)
    
    $pattern = "helium_.*_${Architecture}-installer\.exe$"
    $asset = $Assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    
    if ($asset) {
        Write-Log "Found installer: $($asset.name)"
        return $asset
    }
    
    Write-Log "No installer found for architecture: $Architecture" -Level "ERROR"
    return $null
}

function Get-InstallerUrl {
    param($Assets, [string]$Architecture)
    
    $asset = Get-InstallerAsset -Assets $Assets -Architecture $Architecture
    if ($asset) {
        return $asset.browser_download_url
    }
    return $null
}

function Get-ExpectedChecksum {
    param($Asset)
    
    # GitHub API provides digest in format "sha256:hexstring"
    if ($Asset.digest -and $Asset.digest -match '^sha256:([a-fA-F0-9]{64})$') {
        return $Matches[1].ToUpper()
    }
    return $null
}

function Test-FileChecksum {
    param([string]$FilePath, [string]$ExpectedHash)
    
    if ([string]::IsNullOrEmpty($ExpectedHash)) {
        Write-Log "No checksum available for verification - skipping" -Level "WARN"
        return $true  # Allow install if no checksum available
    }
    
    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        if ($actualHash -eq $ExpectedHash) {
            Write-Log "Checksum verified: $actualHash"
            return $true
        } else {
            Write-Log "Checksum mismatch! Expected: $ExpectedHash, Got: $actualHash" -Level "ERROR"
            return $false
        }
    } catch {
        Write-Log "Checksum calculation failed: $_" -Level "ERROR"
        return $false
    }
}

function Show-UpdateNotification {
    param([string]$CurrentVersion, [string]$NewVersion)
    
    Write-Log "Showing update notification: $CurrentVersion -> $NewVersion"
    
    # Get the script path for the toast action
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = Join-Path $script:AppDataPath "Update-Helium.ps1"
    }
    
    # Try BurntToast first for rich notifications with buttons
    $hasBurntToast = Get-Module -ListAvailable -Name BurntToast
    
    if ($hasBurntToast) {
        try {
            Import-Module BurntToast -ErrorAction Stop
            
            # Build PowerShell command to run the install directly
            $installCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Install -Version `"$NewVersion`""
            
            $installAction = New-BTButton -Content "Install Now" -Arguments $installCommand
            $laterAction = New-BTButton -Content "Not Now" -Arguments "dismiss:"
            
            if ($CurrentVersion) {
                $text1 = New-BTText -Content "Helium Update Available"
                $text2 = New-BTText -Content "Update from $CurrentVersion to $NewVersion"
            } else {
                $text1 = New-BTText -Content "Helium Available"
                $text2 = New-BTText -Content "Version $NewVersion is ready to install."
            }
            
            $binding = New-BTBinding -Children $text1, $text2
            $visual = New-BTVisual -BindingGeneric $binding
            $actions = New-BTAction -Buttons $installAction, $laterAction
            
            $content = New-BTContent -Visual $visual -Actions $actions
            Submit-BTNotification -Content $content
            
            Write-Log "Toast notification sent via BurntToast"
            return
        } catch {
            Write-Log "BurntToast failed: $_ - falling back to MessageBox" -Level "WARN"
        }
    }
    
    # Fallback: MessageBox prompt
    Add-Type -AssemblyName System.Windows.Forms
    
    if ($CurrentVersion) {
        $title = "Helium Update Available"
        $message = "A new version of Helium is available!`n`nCurrent: $CurrentVersion`nNew: $NewVersion`n`nWould you like to update now?"
    } else {
        $title = "Helium Available"
        $message = "Helium browser version $NewVersion is available.`n`nWould you like to install it now?"
    }
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "User chose to install"
        Install-Update -Version $NewVersion
    } else {
        Write-Log "User declined, will ask again next time"
    }
}

function Install-Update {
    param([string]$Version)
    
    # Validate version format to prevent path traversal/injection
    $cleanVersion = $Version -replace '^v', '' -replace '-.*$', ''
    if ($cleanVersion -notmatch $script:VersionPattern) {
        Write-Log "Invalid version format: $Version" -Level "ERROR"
        return $false
    }
    
    Write-Log "Starting update installation for version $Version"
    
    # Get release info
    $release = Get-LatestRelease
    if (-not $release) {
        Write-Log "Failed to get release info for installation" -Level "ERROR"
        return $false
    }
    
    # Verify version matches (in case a newer version was released)
    $releaseClean = $release.Version -replace '^v', '' -replace '-.*$', ''
    if ($releaseClean -ne $cleanVersion) {
        Write-Log "Version mismatch: requested $Version but latest is $($release.Version). Using latest."
        $Version = $release.Version
        $cleanVersion = $releaseClean
    }
    
    $arch = Get-Architecture
    $installerAsset = Get-InstallerAsset -Assets $release.Assets -Architecture $arch
    
    if (-not $installerAsset) {
        Write-Log "Could not find installer" -Level "ERROR"
        return $false
    }
    
    $installerUrl = $installerAsset.browser_download_url
    $expectedChecksum = Get-ExpectedChecksum -Asset $installerAsset
    
    # Download installer with unique filename to prevent race conditions
    $uniqueId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $tempPath = Join-Path $env:TEMP "helium_${cleanVersion}_${arch}_${uniqueId}-installer.exe"
    Write-Log "Downloading installer to: $tempPath"
    
    try {
        Write-Log "Downloading from: $installerUrl"
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($installerUrl, $tempPath)
        
        Write-Log "Download complete"
    } catch {
        Write-Log "Download failed: $_" -Level "ERROR"
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
        return $false
    }
    
    # Verify checksum before execution
    if (-not (Test-FileChecksum -FilePath $tempPath -ExpectedHash $expectedChecksum)) {
        Write-Log "Checksum verification failed - aborting installation for security" -Level "ERROR"
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    
    # Check if Helium is running and wait for user to close it
    $heliumProcess = Get-Process -Name "helium" -ErrorAction SilentlyContinue
    if ($heliumProcess) {
        Write-Log "Helium is running, prompting user to close it"
        Add-Type -AssemblyName System.Windows.Forms
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Helium browser is currently running.`n`nPlease close it to continue with the update.",
            "Close Helium",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Log "User cancelled update due to running browser"
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            return $false
        }
        
        # Wait for user to close Helium
        $timeout = 60
        $waited = 0
        while ((Get-Process -Name "helium" -ErrorAction SilentlyContinue) -and $waited -lt $timeout) {
            Start-Sleep -Seconds 2
            $waited += 2
        }
    }
    
    # Final check immediately before installation (TOCTOU fix)
    if (Get-Process -Name "helium" -ErrorAction SilentlyContinue) {
        Write-Log "Helium still running - cannot proceed with installation" -Level "ERROR"
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    
    # Run installer silently
    Write-Log "Running installer..."
    try {
        $process = Start-Process -FilePath $tempPath -ArgumentList "/S" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Installation completed successfully"
            
            # Update config with new version (use clean version)
            $config = Get-Config
            $config.installedHeliumVersion = $cleanVersion
            $config.lastChecked = (Get-Date).ToString("o")
            Save-Config -Config $config
            
            # Show success notification
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "Helium has been updated to version $cleanVersion",
                "Update Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            return $true
        } else {
            Write-Log "Installer exited with code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
    } catch {
        Write-Log "Installation failed: $_" -Level "ERROR"
        return $false
    } finally {
        # Always clean up installer
        if (Test-Path $tempPath) {
            Write-Log "Cleaning up installer file"
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main execution
function Main {
    Write-Log "========== Helium Updater Started =========="
    
    # Acquire lock to prevent concurrent executions
    if (-not (Get-UpdaterLock)) {
        Write-Log "Could not acquire lock - exiting"
        return
    }
    
    try {
        # If called with -Install flag, go straight to installation
        if ($Install -and $Version) {
            Write-Log "Install requested for version: $Version"
            Install-Update -Version $Version
            return
        }
        
        # Check for updates
        $release = Get-LatestRelease
        if (-not $release) {
            Write-Log "Could not check for updates"
            return
        }
        
        $currentVersion = Get-InstalledVersion
        $latestVersion = $release.Version
        
        Write-Log "Current version: $currentVersion"
        Write-Log "Latest version: $latestVersion"
        
        # Update last checked time
        $config = Get-Config
        $config.lastChecked = (Get-Date).ToString("o")
        Save-Config -Config $config
        
        # Compare versions
        if (Compare-Versions -Current $currentVersion -Latest $latestVersion) {
            Write-Log "Update available!"
            Show-UpdateNotification -CurrentVersion $currentVersion -NewVersion $latestVersion
        } else {
            Write-Log "Already up to date"
        }
    } finally {
        Release-UpdaterLock
        Write-Log "========== Helium Updater Finished =========="
    }
}

Main
