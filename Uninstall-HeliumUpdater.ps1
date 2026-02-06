<#
.SYNOPSIS
    Uninstalls the Helium Browser Auto-Updater
.DESCRIPTION
    Removes scheduled tasks, protocol handler, and cleans up files.
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# Configuration
$script:AppDataPath = Join-Path $env:LOCALAPPDATA "HeliumUpdater"
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

function Unregister-ScheduledTasks {
    Write-Status "Removing scheduled tasks..."
    
    $tasksRemoved = 0
    
    $task = Get-ScheduledTask -TaskName $script:TaskNameLogin -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $script:TaskNameLogin -Confirm:$false
        Write-Status "Removed task: $script:TaskNameLogin" -Type "SUCCESS"
        $tasksRemoved++
    }
    
    $task = Get-ScheduledTask -TaskName $script:TaskNameDaily -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $script:TaskNameDaily -Confirm:$false
        Write-Status "Removed task: $script:TaskNameDaily" -Type "SUCCESS"
        $tasksRemoved++
    }
    
    if ($tasksRemoved -eq 0) {
        Write-Status "No scheduled tasks found" -Type "WARN"
    }
}

function Unregister-ProtocolHandler {
    Write-Status "Removing protocol handler..."
    
    $protocolPath = "HKCU:\Software\Classes\helium-update"
    
    if (Test-Path $protocolPath) {
        Remove-Item $protocolPath -Recurse -Force
        Write-Status "Removed helium-update: protocol handler" -Type "SUCCESS"
    } else {
        Write-Status "Protocol handler not found" -Type "WARN"
    }
}

function Remove-Files {
    Write-Status "Removing files..."
    
    if (Test-Path $script:AppDataPath) {
        Remove-Item $script:AppDataPath -Recurse -Force
        Write-Status "Removed $script:AppDataPath" -Type "SUCCESS"
    } else {
        Write-Status "Installation directory not found" -Type "WARN"
    }
}

function Main {
    try {
        Write-Host ""
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host "  Helium Updater Uninstall      " -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host ""
        
        $confirm = Read-Host "Are you sure you want to uninstall Helium Updater? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Status "Uninstall cancelled" -Type "WARN"
            exit 0
        }
        
        Write-Host ""
        
        Unregister-ScheduledTasks
        Unregister-ProtocolHandler
        Remove-Files
        
        Write-Host ""
        Write-Host "================================" -ForegroundColor Green
        Write-Status "Uninstall complete!" -Type "SUCCESS"
        Write-Host "================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Helium Updater has been removed from your system."
        Write-Host "Note: This does not affect Helium browser itself."
        Write-Host ""
        
    } catch {
        Write-Status "Uninstall failed: $_" -Type "ERROR"
        exit 1
    }
}

# Only run Main when executed directly, not when dot-sourced for testing
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
