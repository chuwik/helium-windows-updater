<#
.SYNOPSIS
    Installs the Helium Browser Auto-Updater
.DESCRIPTION
    Copies scripts to AppData and registers scheduled tasks for automatic updates.
    Run this script once to set up automatic update checking.
#>

#Requires -Version 5.1

param(
    [switch]$Force  # Overwrite existing installation
)

$ErrorActionPreference = "Stop"

# Configuration
$script:AppDataPath = Join-Path $env:LOCALAPPDATA "HeliumUpdater"
$script:SourcePath = $PSScriptRoot
$script:TaskNameLogin = "HeliumUpdater-Login"
$script:TaskNameDaily = "HeliumUpdater-Daily"

function Write-Status {
    param([string]$Message, [string]$Type = "INFO")
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        default { "White" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $color
}

function Install-Scripts {
    Write-Status "Installing scripts to $script:AppDataPath"
    
    # Create directory if needed
    if (-not (Test-Path $script:AppDataPath)) {
        New-Item -ItemType Directory -Path $script:AppDataPath -Force | Out-Null
    }
    
    # Copy main update script
    $sourcescript = Join-Path $script:SourcePath "Update-Helium.ps1"
    $destScript = Join-Path $script:AppDataPath "Update-Helium.ps1"
    
    if (-not (Test-Path $sourcescript)) {
        throw "Update-Helium.ps1 not found in $script:SourcePath"
    }
    
    Copy-Item $sourcescript $destScript -Force
    Write-Status "Copied Update-Helium.ps1" -Type "SUCCESS"
}

function Register-ScheduledTasks {
    Write-Status "Registering scheduled tasks..."
    
    $scriptPath = Join-Path $script:AppDataPath "Update-Helium.ps1"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
    
    # Remove existing tasks if present
    Unregister-ScheduledTask -TaskName $script:TaskNameLogin -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:TaskNameDaily -Confirm:$false -ErrorAction SilentlyContinue
    
    # Task 1: On user login
    $triggerLogin = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName $script:TaskNameLogin -Action $action -Trigger $triggerLogin -Settings $settings -Description "Check for Helium browser updates on login" | Out-Null
    Write-Status "Registered login task: $script:TaskNameLogin" -Type "SUCCESS"
    
    # Task 2: Daily at noon
    $triggerDaily = New-ScheduledTaskTrigger -Daily -At "12:00 PM"
    Register-ScheduledTask -TaskName $script:TaskNameDaily -Action $action -Trigger $triggerDaily -Settings $settings -Description "Check for Helium browser updates daily" | Out-Null
    Write-Status "Registered daily task: $script:TaskNameDaily" -Type "SUCCESS"
}

function Unregister-LegacyProtocolHandler {
    # Clean up old protocol handler if it exists from previous installations
    $protocolPath = "HKCU:\Software\Classes\helium-update"
    
    if (Test-Path $protocolPath) {
        Remove-Item $protocolPath -Recurse -Force
        Write-Status "Removed legacy protocol handler" -Type "SUCCESS"
    }
}

function Initialize-Config {
    $configPath = Join-Path $script:AppDataPath "config.json"
    
    if (-not (Test-Path $configPath)) {
        Write-Status "Creating initial config file..."
        
        # Check if Helium is installed (registry DisplayVersion is Chromium's, not Helium's)
        $heliumInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" 2>$null | Where-Object { $_.DisplayName -like "*helium*" } | Select-Object -First 1
        
        $config = @{
            lastChecked = $null
            installedHeliumVersion = $null
        }
        
        if ($heliumInstalled) {
            Write-Status "Helium browser detected on system" -Type "SUCCESS"
            Write-Status "Version will be determined on next update check" -Type "INFO"
        }
        
        $config | ConvertTo-Json | Set-Content $configPath -Force
    }
}

function Main {
    try {
        Write-Host ""
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host "  Helium Updater Installation   " -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if already installed
        if ((Test-Path $script:AppDataPath) -and -not $Force) {
            $existing = Get-ScheduledTask -TaskName $script:TaskNameLogin -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Status "Helium Updater is already installed." -Type "WARN"
                Write-Host "Use -Force to reinstall, or run Uninstall-HeliumUpdater.ps1 first."
                exit 0
            }
        }
        
        Install-Scripts
        Register-ScheduledTasks
        Unregister-LegacyProtocolHandler
        Initialize-Config
        
        Write-Host ""
        Write-Host "================================" -ForegroundColor Green
        Write-Status "Installation complete!" -Type "SUCCESS"
        Write-Host "================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Helium Updater will now:"
        Write-Host "  - Check for updates when you log in"
        Write-Host "  - Check for updates daily at 12:00 PM"
        Write-Host ""
        Write-Host "You can manually check for updates by running:"
        Write-Host "  & '$script:AppDataPath\Update-Helium.ps1'"
        Write-Host ""
        
        # Offer to run check now or install Helium
        $heliumInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" 2>$null | Where-Object { $_.DisplayName -like "*helium*" } | Select-Object -First 1
        
        if ($heliumInstalled) {
            $runNow = Read-Host "Would you like to check for updates now? (Y/n)"
        } else {
            $runNow = Read-Host "Helium browser is not installed. Would you like to install it now? (Y/n)"
        }
        
        if ($runNow -ne 'n' -and $runNow -ne 'N') {
            Write-Host ""
            & (Join-Path $script:AppDataPath "Update-Helium.ps1")
        }
        
    } catch {
        Write-Status "Installation failed: $_" -Type "ERROR"
        exit 1
    }
}

# Only run Main when executed directly, not when dot-sourced for testing
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
