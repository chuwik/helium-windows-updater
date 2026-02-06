#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Update-Helium.ps1.
    Tests real filesystem operations (config, lock, checksum) without network or installer execution.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Update-Helium.ps1")

    $script:testDir = New-TestDirectory
    $script:AppDataPath = $script:testDir
    $script:ConfigPath = Join-Path $script:testDir "config.json"
    $script:LogPath = Join-Path $script:testDir "test.log"
    $script:LockPath = Join-Path $script:testDir "updater.lock"
}

AfterAll {
    Remove-TestDirectory -Path $script:testDir
}

Describe "Config file round-trip on real filesystem" {
    It "Saves config and reads it back correctly" {
        $config = @{
            installedHeliumVersion = "4.5.6.7"
            lastChecked = (Get-Date).ToString("o")
        }
        Save-Config -Config $config

        Test-Path $script:ConfigPath | Should -BeTrue

        $readBack = Get-Config
        $readBack.installedHeliumVersion | Should -Be "4.5.6.7"
    }

    It "Handles overwriting an existing config" {
        $config1 = @{ installedHeliumVersion = "1.0.0"; lastChecked = $null }
        Save-Config -Config $config1

        $config2 = @{ installedHeliumVersion = "2.0.0"; lastChecked = "2025-12-01" }
        Save-Config -Config $config2

        $readBack = Get-Config
        $readBack.installedHeliumVersion | Should -Be "2.0.0"
    }
}

Describe "Lock file on real filesystem" {
    BeforeEach {
        if (Test-Path $script:LockPath) {
            Remove-Item $script:LockPath -Force
        }
    }

    It "Creates lock file with PID" {
        $result = Get-UpdaterLock
        $result | Should -BeTrue
        Test-Path $script:LockPath | Should -BeTrue

        $lockContent = Get-Content $script:LockPath
        $lockContent | Should -Be $PID.ToString()

        Remove-UpdaterLock
    }

    It "Removes lock file on release" {
        Get-UpdaterLock | Out-Null
        Remove-UpdaterLock
        Test-Path $script:LockPath | Should -BeFalse
    }

    It "Release is safe when no lock exists" {
        { Remove-UpdaterLock } | Should -Not -Throw
    }

    It "Cleans up stale lock and acquires new one" {
        $PID | Set-Content $script:LockPath -Force
        (Get-Item $script:LockPath).LastWriteTime = (Get-Date).AddMinutes(-15)

        $result = Get-UpdaterLock
        $result | Should -BeTrue

        # Lock file should now be fresh
        $lockAge = (Get-Date) - (Get-Item $script:LockPath).LastWriteTime
        $lockAge.TotalMinutes | Should -BeLessThan 1

        Remove-UpdaterLock
    }
}

Describe "Version comparison with real function" {
    It "Correctly identifies a newer version" {
        Compare-Versions -Current "0.7.10" -Latest "0.7.11" | Should -BeTrue
    }

    It "Correctly identifies same version" {
        Compare-Versions -Current "0.7.10.1" -Latest "0.7.10.1" | Should -BeFalse
    }

    It "Handles mixed prefix and suffix versions" {
        Compare-Versions -Current "v0.7.10-beta" -Latest "v0.7.11" | Should -BeTrue
    }

    It "Handles comparing 3-part to 4-part versions" {
        Compare-Versions -Current "1.2.3" -Latest "1.2.3.0" | Should -BeFalse
    }
}

Describe "Checksum verification with real file" {
    BeforeAll {
        $script:checksumTestDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:checksumTestDir
    }

    It "Verifies correct checksum of a real file" {
        $testFile = Join-Path $script:checksumTestDir "checksum-test.txt"
        Set-Content $testFile -Value "Hello, Helium!" -NoNewline

        $expectedHash = (Get-FileHash -Path $testFile -Algorithm SHA256).Hash

        Test-FileChecksum -FilePath $testFile -ExpectedHash $expectedHash | Should -BeTrue
    }

    It "Rejects incorrect checksum" {
        $testFile = Join-Path $script:checksumTestDir "checksum-bad.txt"
        Set-Content $testFile -Value "Hello, Helium!" -NoNewline

        Test-FileChecksum -FilePath $testFile -ExpectedHash "DEADBEEF" 2>$null | Should -BeFalse
    }
}

Describe "Logging to real file" {
    It "Appends log entries to log file" {
        $initialLines = 0
        if (Test-Path $script:LogPath) {
            $initialLines = (Get-Content $script:LogPath).Count
        }

        Write-Log "Integration test log entry"

        Test-Path $script:LogPath | Should -BeTrue
        $lines = Get-Content $script:LogPath
        $lines.Count | Should -BeGreaterThan $initialLines
        $lines[-1] | Should -BeLike "*Integration test log entry*"
    }
}
