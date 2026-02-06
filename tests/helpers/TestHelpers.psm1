<#
.SYNOPSIS
    Shared test helper functions for Helium Updater Pester tests.
#>

function New-TestDirectory {
    <#
    .SYNOPSIS
        Creates an isolated temporary directory for test use.
    #>
    $testDir = Join-Path $env:TEMP "HeliumUpdaterTests_$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    return $testDir
}

function Remove-TestDirectory {
    <#
    .SYNOPSIS
        Removes a test directory created by New-TestDirectory.
    #>
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-MockConfig {
    <#
    .SYNOPSIS
        Creates a config.json file with specified values.
    #>
    param(
        [string]$Path,
        [string]$InstalledVersion = $null,
        [string]$LastChecked = $null
    )
    $config = @{
        installedHeliumVersion = $InstalledVersion
        lastChecked = $LastChecked
    }
    $config | ConvertTo-Json | Set-Content $Path -Force
}

function Get-FixturePath {
    <#
    .SYNOPSIS
        Resolves the full path to a fixture JSON file.
    #>
    param([string]$FixtureName)
    $fixturesDir = Join-Path $PSScriptRoot "..\fixtures"
    return Join-Path $fixturesDir $FixtureName
}

function Get-FixtureContent {
    <#
    .SYNOPSIS
        Reads and parses a fixture JSON file, returning a PSCustomObject.
    #>
    param([string]$FixtureName)
    $path = Get-FixturePath -FixtureName $FixtureName
    return Get-Content $path -Raw | ConvertFrom-Json
}

Export-ModuleMember -Function New-TestDirectory, Remove-TestDirectory, New-MockConfig, Get-FixturePath, Get-FixtureContent
