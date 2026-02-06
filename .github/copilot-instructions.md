# Copilot Instructions

## Project Overview

PowerShell-based auto-updater for [Helium browser](https://github.com/imputnet/helium-windows) on Windows. It polls GitHub releases for new versions, notifies the user, and performs silent installation.

## Architecture

Three standalone PowerShell scripts, each with a specific role:

- **`Update-Helium.ps1`** — Core updater logic. Runs as a scheduled task (on login + daily at noon). Checks GitHub API for the latest release, compares versions, prompts the user, downloads and installs the update. Also handles direct install invocation via `-Install -Version` parameters. Installs Helium directly if not already present.
- **`Install-HeliumUpdater.ps1`** — One-time setup. Copies `Update-Helium.ps1` to `%LOCALAPPDATA%\HeliumUpdater\`, registers two Windows Scheduled Tasks, and creates `config.json`.
- **`Uninstall-HeliumUpdater.ps1`** — Tears down scheduled tasks and the `%LOCALAPPDATA%\HeliumUpdater\` directory.

### Runtime file layout (after installation)

```
%LOCALAPPDATA%\HeliumUpdater\
├── Update-Helium.ps1      # Copied from repo
├── config.json            # Tracks installedHeliumVersion + lastChecked
└── helium-updater.log     # Append-only log
```

## Releases

Tag-triggered GitHub Actions workflow (`.github/workflows/release.yml`). Pushing a `v*` tag builds a zip of the scripts, generates a SHA256 checksum, and creates a GitHub Release with auto-generated notes. The zip includes `Update-Helium.ps1`, `Install-HeliumUpdater.ps1`, `Uninstall-HeliumUpdater.ps1`, `README.md`, and `LICENSE`.

## Testing & CI

- **Build script** — `.\build.ps1` runs lint + tests. Accepts `-Task` parameter: `All` (default), `Lint`, `Test`, `Unit`, `Integration`.
- **Test framework** — Pester v5. Tests live in `tests/Unit/` (57 mocked tests) and `tests/Integration/` (20 tests using real scheduled tasks and filesystem).
- **Linting** — PSScriptAnalyzer with PSGallery ruleset. Excluded rules: `PSAvoidUsingWriteHost`, `PSUseSingularNouns`, `PSUseShouldProcessForStateChangingFunctions` (all intentional in this codebase).
- **CI workflow** — `.github/workflows/ci.yml` runs lint + unit + integration tests on `windows-latest` for PRs and pushes to `main`.
- **Dot-source guard** — All scripts wrap their `Main` call in `if ($MyInvocation.InvocationName -ne '.') { Main }` so Pester can dot-source them without triggering side effects. New scripts must follow this pattern.
- **Test fixtures** — Canned GitHub API responses in `tests/fixtures/`. Tests never make real network calls or run real installers.
- **Test helpers** — `tests/helpers/TestHelpers.psm1` provides `New-TestDirectory`, `Remove-TestDirectory`, `New-MockConfig`, `Get-FixturePath`, `Get-FixtureContent`.
- **Suppressing expected errors** — Tests that exercise error paths use `2>$null` to suppress `Write-Error` noise while still asserting return values.

## Key Conventions

- **PowerShell 5.1 minimum** — All scripts use `#Requires -Version 5.1`. Do not use PowerShell 7+ features (e.g., ternary operator, `&&` chaining, null-coalescing).
- **Script-scoped variables** — Configuration constants use `$script:` scope prefix (e.g., `$script:AppDataPath`, `$script:GitHubApiUrl`).
- **Write-Log pattern** — `Update-Helium.ps1` uses a `Write-Log` function that writes timestamped `[$Level]` entries to the log file and routes errors through `Write-Error` / verbose through `Write-Verbose`. The install/uninstall scripts use a simpler `Write-Status` function with colored console output.
- **Version format** — Versions follow `MAJOR.MINOR.PATCH[.BUILD]` (e.g., `0.7.10.1`). The `$script:VersionPattern` regex validates this. Versions are compared segment-by-segment after stripping `v` prefix and pre-release suffixes.
- **Concurrency control** — A file-based lock (`updater.lock` with PID) prevents concurrent updater executions, with a 10-minute stale lock timeout.
- **Security checks** — Installer downloads are verified via SHA256 checksum from the GitHub API asset digest. Version strings are validated against `$script:VersionPattern` before use in file paths to prevent injection.
- **Notifications** — Uses `System.Windows.Forms.MessageBox` for user prompts (update available, install confirmation).
- **Error handling** — Install/uninstall scripts set `$ErrorActionPreference = "Stop"`. The updater uses try/catch blocks with `Write-Log` for error reporting and always releases the lock in a `finally` block.
- **Conventional Commits** — All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification (e.g., `fix: ...`, `feat: ...`, `chore: ...`, `docs: ...`).
