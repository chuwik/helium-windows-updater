#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Uninstall-HeliumUpdater.ps1")
}

Describe "Unregister-ScheduledTasks" {
    It "Removes both tasks when they exist" {
        $script:TaskNameLogin = "HeliumUpdater-Test-Login"
        $script:TaskNameDaily = "HeliumUpdater-Test-Daily"

        Mock Get-ScheduledTask { return [PSCustomObject]@{ TaskName = $TaskName } }
        Mock Unregister-ScheduledTask {}

        Unregister-ScheduledTasks

        Should -Invoke Unregister-ScheduledTask -Times 2
    }

    It "Handles gracefully when no tasks exist" {
        $script:TaskNameLogin = "HeliumUpdater-Nonexistent-Login"
        $script:TaskNameDaily = "HeliumUpdater-Nonexistent-Daily"

        Mock Get-ScheduledTask { return $null }
        Mock Unregister-ScheduledTask {}

        { Unregister-ScheduledTasks } | Should -Not -Throw
        Should -Invoke Unregister-ScheduledTask -Times 0
    }
}

Describe "Unregister-ProtocolHandler" {
    It "Removes registry key when it exists" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*helium-update*" }
        Mock Remove-Item {}

        Unregister-ProtocolHandler

        Should -Invoke Remove-Item -Times 1
    }

    It "Handles gracefully when registry key does not exist" {
        Mock Test-Path { return $false } -ParameterFilter { $Path -like "*helium-update*" }
        Mock Remove-Item {}

        Unregister-ProtocolHandler

        Should -Invoke Remove-Item -Times 0
    }
}

Describe "Remove-Files" {
    It "Removes directory when it exists" {
        $testDir = New-TestDirectory
        $script:AppDataPath = $testDir

        Remove-Files

        Test-Path $testDir | Should -BeFalse
    }

    It "Handles gracefully when directory does not exist" {
        $script:AppDataPath = Join-Path $env:TEMP "NonexistentHeliumDir_$(New-Guid)"

        { Remove-Files } | Should -Not -Throw
    }
}
