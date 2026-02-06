#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Uninstall-HeliumUpdater.ps1.
    Sets up a real installation, then verifies full teardown.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Install-HeliumUpdater.ps1")

    $script:testDir = New-TestDirectory
    $script:testSourceDir = New-TestDirectory

    # Create fake source
    Set-Content (Join-Path $script:testSourceDir "Update-Helium.ps1") -Value "# Uninstall test"

    # Override variables
    $script:AppDataPath = $script:testDir
    $script:SourcePath = $script:testSourceDir
    $script:TaskNameLogin = "HeliumUpdater-UninstTest-Login"
    $script:TaskNameDaily = "HeliumUpdater-UninstTest-Daily"

    # Set up: run install to create the things we'll tear down
    Install-Scripts
    Register-ScheduledTasks
}

AfterAll {
    # Safety cleanup in case tests fail
    Unregister-ScheduledTask -TaskName "HeliumUpdater-UninstTest-Login" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "HeliumUpdater-UninstTest-Daily" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-TestDirectory -Path $script:testDir
    Remove-TestDirectory -Path $script:testSourceDir
}

Describe "Full uninstall flow" {
    BeforeAll {
        # Now dot-source the uninstall script to get its functions
        . (Join-Path $PSScriptRoot "..\..\Uninstall-HeliumUpdater.ps1")

        # Re-apply overrides (dot-sourcing resets script-scope vars)
        $script:AppDataPath = $script:testDir
        $script:TaskNameLogin = "HeliumUpdater-UninstTest-Login"
        $script:TaskNameDaily = "HeliumUpdater-UninstTest-Daily"
    }

    It "Removes scheduled tasks" {
        Unregister-ScheduledTasks

        $loginTask = Get-ScheduledTask -TaskName "HeliumUpdater-UninstTest-Login" -ErrorAction SilentlyContinue
        $loginTask | Should -BeNullOrEmpty

        $dailyTask = Get-ScheduledTask -TaskName "HeliumUpdater-UninstTest-Daily" -ErrorAction SilentlyContinue
        $dailyTask | Should -BeNullOrEmpty
    }

    It "Removes the installation directory" {
        # Recreate dir since we need it to exist for this test
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        Set-Content (Join-Path $script:testDir "dummy.txt") -Value "test"

        Remove-Files

        Test-Path $script:testDir | Should -BeFalse
    }
}

Describe "Uninstall on clean system" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\..\Uninstall-HeliumUpdater.ps1")

        $script:AppDataPath = Join-Path $env:TEMP "HeliumUpdater_Nonexistent_$(New-Guid)"
        $script:TaskNameLogin = "HeliumUpdater-CleanTest-Login"
        $script:TaskNameDaily = "HeliumUpdater-CleanTest-Daily"
    }

    It "Does not error when nothing is installed" {
        { Unregister-ScheduledTasks } | Should -Not -Throw
        { Remove-Files } | Should -Not -Throw
    }
}
