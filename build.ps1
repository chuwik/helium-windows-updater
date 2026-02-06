<#
.SYNOPSIS
    Build script for Helium Windows Updater — runs lint and tests locally.
.EXAMPLE
    .\build.ps1              # Run everything (lint + unit + integration tests)
    .\build.ps1 -Task Lint   # Run only PSScriptAnalyzer
    .\build.ps1 -Task Unit   # Run only unit tests
    .\build.ps1 -Task Integration  # Run only integration tests
    .\build.ps1 -Task Test   # Run unit + integration tests
#>

param(
    [ValidateSet("All", "Lint", "Test", "Unit", "Integration")]
    [string]$Task = "All"
)

$ErrorActionPreference = "Stop"
$failed = $false

function Invoke-Lint {
    Write-Host "`n=== PSScriptAnalyzer ===" -ForegroundColor Cyan

    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Host "Installing PSScriptAnalyzer..." -ForegroundColor Yellow
        Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
    }

    $results = Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse -Settings PSGallery `
        -ExcludeRule PSAvoidUsingWriteHost, PSUseSingularNouns, PSUseShouldProcessForStateChangingFunctions

    if ($results) {
        $results | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize
        Write-Host "FAILED: $($results.Count) issue(s) found" -ForegroundColor Red
        return $false
    }

    Write-Host "PASSED" -ForegroundColor Green
    return $true
}

function Invoke-Tests {
    param([string]$Path, [string]$Label)

    Write-Host "`n=== $Label ===" -ForegroundColor Cyan

    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge "5.0.0" })) {
        Write-Host "Installing Pester v5..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -Scope CurrentUser -MinimumVersion 5.0.0
    }

    # Pester tests need Continue so Write-Error in tested error paths doesn't terminate
    $ErrorActionPreference = "Continue"

    $config = New-PesterConfiguration
    $config.Run.Path = $Path
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $config

    if ($result.FailedCount -gt 0) {
        Write-Host "FAILED: $($result.FailedCount) test(s) failed" -ForegroundColor Red
        return $false
    }

    Write-Host "PASSED: $($result.TotalCount) test(s)" -ForegroundColor Green
    return $true
}

# Run requested tasks
switch ($Task) {
    "Lint"        { if (-not (Invoke-Lint)) { $failed = $true } }
    "Unit"        { if (-not (Invoke-Tests "$PSScriptRoot\tests\Unit" "Unit Tests")) { $failed = $true } }
    "Integration" { if (-not (Invoke-Tests "$PSScriptRoot\tests\Integration" "Integration Tests")) { $failed = $true } }
    "Test"        {
        if (-not (Invoke-Tests "$PSScriptRoot\tests\Unit" "Unit Tests")) { $failed = $true }
        if (-not (Invoke-Tests "$PSScriptRoot\tests\Integration" "Integration Tests")) { $failed = $true }
    }
    "All"         {
        if (-not (Invoke-Lint)) { $failed = $true }
        if (-not (Invoke-Tests "$PSScriptRoot\tests\Unit" "Unit Tests")) { $failed = $true }
        if (-not (Invoke-Tests "$PSScriptRoot\tests\Integration" "Integration Tests")) { $failed = $true }
    }
}

# Summary
Write-Host ""
if ($failed) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "BUILD SUCCEEDED" -ForegroundColor Green
}
