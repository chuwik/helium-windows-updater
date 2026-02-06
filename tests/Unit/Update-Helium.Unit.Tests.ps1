#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "..\helpers\TestHelpers.psm1") -Force
    . (Join-Path $PSScriptRoot "..\..\Update-Helium.ps1")
}

Describe "Compare-Versions" {
    It "Returns true when latest is newer" {
        Compare-Versions -Current "1.0.0" -Latest "2.0.0" | Should -BeTrue
    }

    It "Returns false when versions are equal" {
        Compare-Versions -Current "2.0.0" -Latest "2.0.0" | Should -BeFalse
    }

    It "Returns true when 4-part latest is newer than 3-part current" {
        Compare-Versions -Current "1.0.0" -Latest "1.0.0.1" | Should -BeTrue
    }

    It "Returns false when 3-part equals 4-part with zero build" {
        Compare-Versions -Current "1.0.0.0" -Latest "1.0.0" | Should -BeFalse
    }

    It "Strips v-prefix before comparing" {
        Compare-Versions -Current "v1.0.0" -Latest "v2.0.0" | Should -BeTrue
    }

    It "Handles pre-release suffix gracefully" {
        # Pre-release suffix is stripped; "1.0.0-beta" becomes "1.0.0"
        Compare-Versions -Current "1.0.0-beta" -Latest "1.0.0" | Should -BeFalse
    }

    It "Returns true when current is null" {
        Compare-Versions -Current $null -Latest "2.0.0" | Should -BeTrue
    }

    It "Returns true when current is empty string" {
        Compare-Versions -Current "" -Latest "2.0.0" | Should -BeTrue
    }

    It "Returns false when latest is older (downgrade)" {
        Compare-Versions -Current "3.0.0" -Latest "2.0.0" | Should -BeFalse
    }

    It "Handles multi-digit segments correctly" {
        Compare-Versions -Current "0.7.9" -Latest "0.7.10" | Should -BeTrue
    }

    It "Returns false when current is newer in minor" {
        Compare-Versions -Current "1.2.0" -Latest "1.1.0" | Should -BeFalse
    }
}

Describe "Get-Architecture" {
    It "Returns x64 for AMD64" {
        $originalArch = $env:PROCESSOR_ARCHITECTURE
        try {
            $env:PROCESSOR_ARCHITECTURE = "AMD64"
            Get-Architecture | Should -Be "x64"
        } finally {
            $env:PROCESSOR_ARCHITECTURE = $originalArch
        }
    }

    It "Returns arm64 for ARM64" {
        $originalArch = $env:PROCESSOR_ARCHITECTURE
        try {
            $env:PROCESSOR_ARCHITECTURE = "ARM64"
            Get-Architecture | Should -Be "arm64"
        } finally {
            $env:PROCESSOR_ARCHITECTURE = $originalArch
        }
    }
}

Describe "Get-InstallerAsset" {
    BeforeAll {
        $script:fixtureAssets = (Get-FixtureContent "release-latest.json").assets
    }

    It "Finds x64 installer asset" {
        $asset = Get-InstallerAsset -Assets $script:fixtureAssets -Architecture "x64"
        $asset | Should -Not -BeNullOrEmpty
        $asset.name | Should -BeLike "*x64-installer.exe"
    }

    It "Finds arm64 installer asset" {
        $asset = Get-InstallerAsset -Assets $script:fixtureAssets -Architecture "arm64"
        $asset | Should -Not -BeNullOrEmpty
        $asset.name | Should -BeLike "*arm64-installer.exe"
    }

    It "Returns null when no matching asset exists" {
        $asset = Get-InstallerAsset -Assets @() -Architecture "x64" 2>$null
        $asset | Should -BeNullOrEmpty
    }

    It "Returns null for unknown architecture" {
        $asset = Get-InstallerAsset -Assets $script:fixtureAssets -Architecture "mips" 2>$null
        $asset | Should -BeNullOrEmpty
    }
}

Describe "Get-InstallerUrl" {
    BeforeAll {
        $script:fixtureAssets = (Get-FixtureContent "release-latest.json").assets
    }

    It "Returns download URL for matching architecture" {
        $url = Get-InstallerUrl -Assets $script:fixtureAssets -Architecture "x64"
        $url | Should -BeLike "https://github.com/*x64-installer.exe"
    }

    It "Returns null when no asset matches" {
        $url = Get-InstallerUrl -Assets @() -Architecture "x64" 2>$null
        $url | Should -BeNullOrEmpty
    }
}

Describe "Get-ExpectedChecksum" {
    It "Extracts uppercase hex from valid sha256 digest" {
        $asset = [PSCustomObject]@{ digest = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }
        $result = Get-ExpectedChecksum -Asset $asset
        $result | Should -Be "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"
    }

    It "Returns null when digest is missing" {
        $asset = [PSCustomObject]@{ digest = $null }
        $result = Get-ExpectedChecksum -Asset $asset
        $result | Should -BeNullOrEmpty
    }

    It "Returns null when digest has wrong format" {
        $asset = [PSCustomObject]@{ digest = "md5:abc123" }
        $result = Get-ExpectedChecksum -Asset $asset
        $result | Should -BeNullOrEmpty
    }
}

Describe "Test-FileChecksum" {
    BeforeAll {
        $script:testDir = New-TestDirectory
        $script:testFile = Join-Path $script:testDir "testfile.bin"
        Set-Content $script:testFile -Value "test content for checksum" -NoNewline
        $script:actualHash = (Get-FileHash -Path $script:testFile -Algorithm SHA256).Hash
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    It "Returns true when checksum matches" {
        Test-FileChecksum -FilePath $script:testFile -ExpectedHash $script:actualHash | Should -BeTrue
    }

    It "Returns false when checksum mismatches" {
        Test-FileChecksum -FilePath $script:testFile -ExpectedHash "0000000000000000000000000000000000000000000000000000000000000000" 2>$null | Should -BeFalse
    }

    It "Returns true when expected hash is null (skip verification)" {
        Test-FileChecksum -FilePath $script:testFile -ExpectedHash $null | Should -BeTrue
    }

    It "Returns true when expected hash is empty string" {
        Test-FileChecksum -FilePath $script:testFile -ExpectedHash "" | Should -BeTrue
    }
}

Describe "Get-Config" {
    BeforeAll {
        $script:testDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    It "Reads valid config file" {
        $configPath = Join-Path $script:testDir "config.json"
        $script:ConfigPath = $configPath
        New-MockConfig -Path $configPath -InstalledVersion "1.2.3" -LastChecked "2025-01-01T00:00:00Z"

        $config = Get-Config
        $config.installedHeliumVersion | Should -Be "1.2.3"
        $config.lastChecked.ToString() | Should -BeLike "*/2025*"
    }

    It "Returns default when config file is missing" {
        $script:ConfigPath = Join-Path $script:testDir "nonexistent.json"

        $config = Get-Config
        $config.installedHeliumVersion | Should -BeNullOrEmpty
        $config.lastChecked | Should -BeNullOrEmpty
    }

    It "Returns default when config file contains invalid JSON" {
        $configPath = Join-Path $script:testDir "corrupt.json"
        $script:ConfigPath = $configPath
        Set-Content $configPath -Value "not valid json {{{"

        $config = Get-Config 2>$null
        $config.installedHeliumVersion | Should -BeNullOrEmpty
    }
}

Describe "Save-Config" {
    BeforeAll {
        $script:testDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    It "Saves and reads back config correctly" {
        $configPath = Join-Path $script:testDir "config-save.json"
        $script:ConfigPath = $configPath

        $config = @{
            installedHeliumVersion = "2.0.0"
            lastChecked = "2025-06-15T12:00:00Z"
        }
        Save-Config -Config $config

        $read = Get-Content $configPath -Raw | ConvertFrom-Json
        $read.installedHeliumVersion | Should -Be "2.0.0"
        $read.lastChecked.ToString() | Should -BeLike "*/2025*"
    }
}

Describe "Get-LatestRelease" {
    It "Parses GitHub API response correctly" {
        $fixture = Get-FixtureContent "release-latest.json"
        Mock Invoke-RestMethod { return $fixture }

        $result = Get-LatestRelease
        $result | Should -Not -BeNullOrEmpty
        $result.Version | Should -Be "v99.0.0"
        $result.Assets | Should -HaveCount 2
    }

    It "Returns null on API failure" {
        Mock Invoke-RestMethod { throw "Network error" }

        $result = Get-LatestRelease 2>$null
        $result | Should -BeNullOrEmpty
    }
}

Describe "Lock file management" {
    BeforeAll {
        $script:testDir = New-TestDirectory
        $script:LockPath = Join-Path $script:testDir "updater.lock"
        $script:LogPath = Join-Path $script:testDir "test.log"
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    BeforeEach {
        if (Test-Path $script:LockPath) {
            Remove-Item $script:LockPath -Force
        }
    }

    It "Acquires lock by creating lock file" {
        $result = Get-UpdaterLock
        $result | Should -BeTrue
        Test-Path $script:LockPath | Should -BeTrue
    }

    It "Releases lock by removing lock file" {
        Get-UpdaterLock | Out-Null
        Remove-UpdaterLock
        Test-Path $script:LockPath | Should -BeFalse
    }

    It "Cleans up stale lock older than 10 minutes" {
        # Create a lock file and backdate it
        $PID | Set-Content $script:LockPath -Force
        (Get-Item $script:LockPath).LastWriteTime = (Get-Date).AddMinutes(-15)

        $result = Get-UpdaterLock
        $result | Should -BeTrue
    }
}

Describe "Test-HeliumInstalled" {
    It "Returns false when Helium is not in registry" {
        Mock Get-ItemProperty { return @() }
        Test-HeliumInstalled | Should -BeFalse
    }

    It "Returns true when Helium is found in registry" {
        Mock Get-ItemProperty { return @([PSCustomObject]@{ DisplayName = "Helium Browser" }) }
        Test-HeliumInstalled | Should -BeTrue
    }
}

Describe "Get-InstalledVersion" {
    BeforeAll {
        $script:testDir = New-TestDirectory
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    It "Returns version from config" {
        $configPath = Join-Path $script:testDir "config-ver.json"
        $script:ConfigPath = $configPath
        New-MockConfig -Path $configPath -InstalledVersion "3.0.0"

        Get-InstalledVersion | Should -Be "3.0.0"
    }

    It "Returns null when no version in config" {
        $configPath = Join-Path $script:testDir "config-nover.json"
        $script:ConfigPath = $configPath
        New-MockConfig -Path $configPath

        Get-InstalledVersion | Should -BeNullOrEmpty
    }
}

Describe "Main flow" {
    BeforeAll {
        $script:testDir = New-TestDirectory
        $script:AppDataPath = $script:testDir
        $script:ConfigPath = Join-Path $script:testDir "config.json"
        $script:LogPath = Join-Path $script:testDir "test.log"
        $script:LockPath = Join-Path $script:testDir "updater.lock"
    }

    AfterAll {
        Remove-TestDirectory -Path $script:testDir
    }

    BeforeEach {
        if (Test-Path $script:LockPath) {
            Remove-Item $script:LockPath -Force
        }
    }

    It "Does not trigger install when already up to date" {
        $fixture = Get-FixtureContent "release-current.json"
        New-MockConfig -Path $script:ConfigPath -InstalledVersion "1.0.0"

        Mock Invoke-RestMethod { return $fixture }
        Mock Test-HeliumInstalled { return $true }
        Mock Show-UpdateNotification {}
        Mock Install-Update {}

        Main

        Should -Invoke Install-Update -Times 0
        Should -Invoke Show-UpdateNotification -Times 0
    }

    It "Shows notification when update is available" {
        $fixture = Get-FixtureContent "release-latest.json"
        New-MockConfig -Path $script:ConfigPath -InstalledVersion "1.0.0"

        Mock Invoke-RestMethod { return $fixture }
        Mock Test-HeliumInstalled { return $true }
        Mock Show-UpdateNotification {}

        Main

        Should -Invoke Show-UpdateNotification -Times 1
    }

    It "Installs directly when Helium is not installed" {
        $fixture = Get-FixtureContent "release-latest.json"
        New-MockConfig -Path $script:ConfigPath

        Mock Invoke-RestMethod { return $fixture }
        Mock Test-HeliumInstalled { return $false }
        Mock Install-Update { return $true }

        Main

        Should -Invoke Install-Update -Times 1
    }
}
