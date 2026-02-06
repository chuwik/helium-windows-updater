#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Install-HeliumUpdater.ps1.
    These tests register REAL scheduled tasks and write to the REAL filesystem.
    All resources are cleaned up in AfterAll.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Install-HeliumUpdater.ps1")

    $script:testDir = New-TestDirectory
    $script:testSourceDir = New-TestDirectory

    # Create a fake Update-Helium.ps1 source
    Set-Content (Join-Path $script:testSourceDir "Update-Helium.ps1") -Value "# Integration test script"

    # Override script-scoped variables to isolate from real installation
    $script:AppDataPath = $script:testDir
    $script:SourcePath = $script:testSourceDir
    $script:TaskNameLogin = "HeliumUpdater-IntTest-Login"
    $script:TaskNameDaily = "HeliumUpdater-IntTest-Daily"
}

AfterAll {
    # Clean up scheduled tasks
    Unregister-ScheduledTask -TaskName "HeliumUpdater-IntTest-Login" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "HeliumUpdater-IntTest-Daily" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-TestDirectory -Path $script:testDir
    Remove-TestDirectory -Path $script:testSourceDir
}

Describe "Full installation flow" {
    It "Copies the update script to the target directory" {
        Install-Scripts

        $destFile = Join-Path $script:testDir "Update-Helium.ps1"
        Test-Path $destFile | Should -BeTrue
        Get-Content $destFile | Should -Be "# Integration test script"
    }

    It "Registers real scheduled tasks" {
        Register-ScheduledTasks

        $loginTask = Get-ScheduledTask -TaskName $script:TaskNameLogin -ErrorAction SilentlyContinue
        $loginTask | Should -Not -BeNullOrEmpty
        $loginTask.TaskName | Should -Be $script:TaskNameLogin

        $dailyTask = Get-ScheduledTask -TaskName $script:TaskNameDaily -ErrorAction SilentlyContinue
        $dailyTask | Should -Not -BeNullOrEmpty
        $dailyTask.TaskName | Should -Be $script:TaskNameDaily
    }

    It "Creates config.json with correct structure" {
        Mock Get-ItemProperty { return @() }

        Initialize-Config

        $configPath = Join-Path $script:testDir "config.json"
        Test-Path $configPath | Should -BeTrue

        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.PSObject.Properties.Name | Should -Contain "installedHeliumVersion"
        $config.PSObject.Properties.Name | Should -Contain "lastChecked"
    }
}

Describe "Force reinstall" {
    It "Re-registers tasks when called again with same names" {
        # Tasks already exist from previous test
        { Register-ScheduledTasks } | Should -Not -Throw

        $loginTask = Get-ScheduledTask -TaskName $script:TaskNameLogin -ErrorAction SilentlyContinue
        $loginTask | Should -Not -BeNullOrEmpty
    }
}
