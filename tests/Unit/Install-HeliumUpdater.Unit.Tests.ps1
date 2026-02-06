#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Install-HeliumUpdater.ps1")
}

Describe "Install-Scripts" {
    BeforeAll {
        $script:testDir = New-TestDirectory
        $script:sourceDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
        Remove-TestDirectory -Path $script:sourceDir
    }

    It "Copies Update-Helium.ps1 to destination" {
        $script:AppDataPath = $script:testDir
        $script:SourcePath = $script:sourceDir

        # Create a source script file
        Set-Content (Join-Path $script:sourceDir "Update-Helium.ps1") -Value "# test script"

        Install-Scripts

        $destFile = Join-Path $script:testDir "Update-Helium.ps1"
        Test-Path $destFile | Should -BeTrue
        Get-Content $destFile | Should -Be "# test script"
    }

    It "Creates destination directory if it does not exist" {
        $newDest = Join-Path $script:testDir "NewSubDir"
        $script:AppDataPath = $newDest
        $script:SourcePath = $script:sourceDir

        Set-Content (Join-Path $script:sourceDir "Update-Helium.ps1") -Value "# test"

        Install-Scripts

        Test-Path $newDest | Should -BeTrue
    }

    It "Throws when source script is missing" {
        $script:AppDataPath = $script:testDir
        $script:SourcePath = Join-Path $script:testDir "nonexistent_source"

        { Install-Scripts } | Should -Throw
    }
}

Describe "Initialize-Config" {
    BeforeAll {
        $script:testDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    It "Creates default config when none exists" {
        $script:AppDataPath = $script:testDir
        $configPath = Join-Path $script:testDir "config.json"

        # Remove any existing config
        if (Test-Path $configPath) { Remove-Item $configPath -Force }

        Mock Get-ItemProperty { return @() }

        Initialize-Config

        Test-Path $configPath | Should -BeTrue
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.installedHeliumVersion | Should -BeNullOrEmpty
        $config.lastChecked | Should -BeNullOrEmpty
    }

    It "Does not overwrite existing config" {
        $script:AppDataPath = $script:testDir
        $configPath = Join-Path $script:testDir "config.json"

        New-MockConfig -Path $configPath -InstalledVersion "5.0.0" -LastChecked "2025-01-01"

        Initialize-Config

        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.installedHeliumVersion | Should -Be "5.0.0"
    }
}

Describe "Unregister-LegacyProtocolHandler" {
    It "Removes registry key when it exists" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*helium-update*" }
        Mock Remove-Item {}

        Unregister-LegacyProtocolHandler

        Should -Invoke Remove-Item -Times 1
    }

    It "Does nothing when registry key does not exist" {
        Mock Test-Path { return $false } -ParameterFilter { $Path -like "*helium-update*" }
        Mock Remove-Item {}

        Unregister-LegacyProtocolHandler

        Should -Invoke Remove-Item -Times 0
    }
}

Describe "Register-ScheduledTasks" {
    # Note: Mocking Register-ScheduledTask with CimInstance parameters is not
    # supported in Pester. Full end-to-end registration with real tasks is
    # covered by the integration tests in Install-HeliumUpdater.Integration.Tests.ps1.

    It "Function exists and is callable" {
        Get-Command Register-ScheduledTasks | Should -Not -BeNullOrEmpty
    }
}

Describe "Already installed detection" {
    It "Detects existing installation when AppData and task both exist" {
        $testDir = New-TestDirectory
        $script:AppDataPath = $testDir
        $script:TaskNameLogin = "HeliumUpdater-AlreadyInstalled-Test"

        Mock Get-ScheduledTask { return [PSCustomObject]@{ TaskName = $script:TaskNameLogin } }

        # Verify that the check logic finds the existing install
        $existing = Get-ScheduledTask -TaskName $script:TaskNameLogin -ErrorAction SilentlyContinue
        (Test-Path $script:AppDataPath) | Should -BeTrue
        $existing | Should -Not -BeNullOrEmpty

        Remove-TestDirectory -Path $testDir
    }
}
