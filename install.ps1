#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    DFCA Installer — Installs "Don't Forget Commands Again" globally.
.DESCRIPTION
    Copies the DFCA tool to $HOME/.config/dfca/ and adds its bin/ directory
    to the User PATH so you can type "dfca" from any terminal (PowerShell or CMD).
.NOTES
    Run once:  pwsh -File install.ps1
    Then open a NEW terminal and type: dfca
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ── Configuration ─────────────────────────────────────────────
$installDir = Join-Path $HOME '.config' 'dfca'
$binDir     = Join-Path $installDir 'bin'
$sourceRoot = $PSScriptRoot  # The directory where this install.ps1 lives

# ── Banner ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║                                                  ║" -ForegroundColor DarkCyan
Write-Host "  ║   DFCA Installer                                 ║" -ForegroundColor Cyan
Write-Host "  ║   Don't Forget Commands Again                    ║" -ForegroundColor DarkGray
Write-Host "  ║                                                  ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

# ── Step 1: Validate source files ────────────────────────────
$requiredDirs = @('bin', 'modules', 'data')
foreach ($dir in $requiredDirs) {
    $path = Join-Path $sourceRoot $dir
    if (-not (Test-Path $path)) {
        Write-Host "  ❌ Missing required directory: $dir" -ForegroundColor Red
        Write-Host "     Expected at: $path" -ForegroundColor DarkGray
        exit 1
    }
}
Write-Host "  ✅ Source files validated." -ForegroundColor Green

# ── Step 2: Create install directory ──────────────────────────
Write-Host "  ⏳ Installing to: $installDir" -ForegroundColor DarkGray

if (Test-Path $installDir) {
    Write-Host "  ⚠  Existing installation found — updating (your snippets are safe)..." -ForegroundColor Yellow

    # Remove only bin/ and modules/ — keep data/ intact
    $updateDirs = @('bin', 'modules')
    foreach ($dir in $updateDirs) {
        $target = Join-Path $installDir $dir
        if (Test-Path $target) {
            Remove-Item -Path $target -Recurse -Force
        }
    }
}
else {
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null
}

# ── Step 3: Copy project files ────────────────────────────────
# Always copy bin/ and modules/
foreach ($dir in @('bin', 'modules')) {
    $src = Join-Path $sourceRoot $dir
    $dst = Join-Path $installDir $dir
    Copy-Item -Path $src -Destination $dst -Recurse -Force
}

# Only copy data/ if it doesn't exist yet (fresh install)
$dataDir = Join-Path $installDir 'data'
if (-not (Test-Path $dataDir)) {
    $src = Join-Path $sourceRoot 'data'
    Copy-Item -Path $src -Destination $dataDir -Recurse -Force
    Write-Host "  ✅ Default snippets installed." -ForegroundColor Green
}
else {
    Write-Host "  ✅ Your existing snippets preserved." -ForegroundColor Green
}
Write-Host "  ✅ Files copied." -ForegroundColor Green

# ── Step 4: Create CMD shim (dfca.cmd) ───────────────────────
$cmdShim = Join-Path $binDir 'dfca.cmd'
$cmdContent = @"
@echo off
pwsh -NoProfile -File "%~dp0dfca.ps1" %*
"@
Set-Content -Path $cmdShim -Value $cmdContent -Encoding ascii
Write-Host "  ✅ CMD shim created (dfca.cmd)." -ForegroundColor Green

# ── Step 5: Add bin/ to User PATH (persistent) ───────────────
$currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries     = $currentUserPath -split ';' | Where-Object { $_ -ne '' }

if ($pathEntries -notcontains $binDir) {
    $newUserPath = ($pathEntries + $binDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    # Also update the current session so it works immediately in this shell
    $env:Path += ";$binDir"
    Write-Host "  ✅ Added to User PATH: $binDir" -ForegroundColor Green
}
else {
    Write-Host "  ✅ PATH already contains: $binDir" -ForegroundColor Green
}

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                                                  ║" -ForegroundColor Green
Write-Host "  ║   ✅ DFCA installed successfully!                ║" -ForegroundColor Green
Write-Host "  ║                                                  ║" -ForegroundColor Green
Write-Host "  ║   Open a NEW terminal and type:  dfca            ║" -ForegroundColor White
Write-Host "  ║                                                  ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Install location : $installDir" -ForegroundColor DarkGray
Write-Host "  Snippets file    : $(Join-Path $installDir 'data' 'snippets.yaml')" -ForegroundColor DarkGray
Write-Host ""
