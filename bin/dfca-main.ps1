#!/usr/bin/env pwsh
<#
.SYNOPSIS
    DFCA — Don't Forget Commands Again (Main Entry Point)
.DESCRIPTION
    A local-first CLI tool to search, select, and inject complex DevOps commands.
    Uses fzf for fuzzy-finding and YAML for the snippet library.
.NOTES
    This file is called by dfca.ps1 (the launcher). Do not run directly.
#>

param(
    [switch]$Save,
    [switch]$List,
    [switch]$Remove,
    [switch]$Edit,
    [Alias('c')][string]$Command,
    [Alias('n')][string]$Name,
    [Alias('cat')][string]$Category,
    [Alias('t')][string]$Tags,
    [Alias('d')][string]$Description
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ── Resolve Paths ─────────────────────────────────────────────
$scriptRoot  = Split-Path -Parent $PSScriptRoot   # project root (parent of /bin)
$modulesPath = Join-Path $scriptRoot 'modules'
$dataPath    = Join-Path $scriptRoot 'data'

# ── Import Modules ────────────────────────────────────────────
try {
    Import-Module (Join-Path $modulesPath 'DFCA.Utils.psm1')    -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath 'DFCA.UI.psm1')       -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesPath 'DFCA.Snippets.psm1') -Force -ErrorAction Stop
}
catch {
    Write-Host "[DFCA] Failed to load modules from: $modulesPath" -ForegroundColor Red
    Write-Host "       Error: $_" -ForegroundColor Red
    exit 1
}

# ── Banner ────────────────────────────────────────────────────
function Show-DFCABanner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║                                                  ║" -ForegroundColor DarkCyan
    Write-Host "  ║   ██████╗ ███████╗ ██████╗ █████╗               ║" -ForegroundColor Cyan
    Write-Host "  ║   ██╔══██╗██╔════╝██╔════╝██╔══██╗              ║" -ForegroundColor Cyan
    Write-Host "  ║   ██║  ██║█████╗  ██║     ███████║              ║" -ForegroundColor Cyan
    Write-Host "  ║   ██║  ██║██╔══╝  ██║     ██╔══██║              ║" -ForegroundColor Cyan
    Write-Host "  ║   ██████╔╝██║     ╚██████╗██║  ██║              ║" -ForegroundColor Cyan
    Write-Host "  ║   ╚═════╝ ╚═╝      ╚═════╝╚═╝  ╚═╝              ║" -ForegroundColor Cyan
    Write-Host "  ║                                                  ║" -ForegroundColor DarkCyan
    Write-Host "  ║   Don't Forget Commands Again                    ║" -ForegroundColor DarkGray
    Write-Host "  ║   Search · Select · Inject                       ║" -ForegroundColor DarkGray
    Write-Host "  ║   By Amine Jameli                                 ║" -ForegroundColor DarkGray
    Write-Host "  ║                                                  ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
}

# ── Action: Save ──────────────────────────────────────────────
function Invoke-DFCASave {
    Show-DFCABanner

    # Ensure YAML module is available
    if (-not (Install-DFCAYamlModule)) { exit 1 }

    if ([string]::IsNullOrWhiteSpace($Command) -or [string]::IsNullOrWhiteSpace($Name)) {
        # Interactive mode — prompt for all fields
        Invoke-DFCAInteractiveSave -DataPath $dataPath
    }
    else {
        # Inline mode — use provided params
        $cat  = if ([string]::IsNullOrWhiteSpace($Category)) { 'general' } else { $Category }
        $tgs  = if ([string]::IsNullOrWhiteSpace($Tags))     { '' }        else { $Tags }
        $desc = if ([string]::IsNullOrWhiteSpace($Description)) { '' }     else { $Description }

        Save-DFCASnippet -DataPath $dataPath -Name $Name -Command $Command -Category $cat -Tags $tgs -Description $desc
    }
}

# ── Action: List ──────────────────────────────────────────────
function Invoke-DFCAList {
    Show-DFCABanner

    if (-not (Install-DFCAYamlModule)) { exit 1 }

    $snippets = @(Get-DFCASnippets -DataPath $dataPath)
    if ($snippets.Count -eq 0) {
        Write-Host "  📭 No snippets saved yet." -ForegroundColor DarkGray
        Write-Host "  Use: dfca --save -c `"your command`" -n `"name`"`n" -ForegroundColor Yellow
        return
    }

    Show-DFCASnippetList -Snippets $snippets
}

# ── Action: Remove ────────────────────────────────────────────
function Invoke-DFCARemove {
    Show-DFCABanner

    if (-not (Install-DFCAYamlModule)) { exit 1 }
    if (-not (Test-DFCADependency))    { exit 1 }

    $snippets = @(Get-DFCASnippets -DataPath $dataPath)
    if ($snippets.Count -eq 0) {
        Write-Host "  📭 No snippets to remove." -ForegroundColor DarkGray
        return
    }

    # Use fzf to select which snippet to remove
    $selected = Invoke-DFCASelector -Snippets $snippets
    if ($null -eq $selected) { return }

    # Confirm deletion
    Write-Host ""
    Write-Host "  ⚠  Remove '$($selected.Name)'?" -ForegroundColor Yellow
    Write-Host "  Command: $($selected.Command)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Type 'yes' to confirm: " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host

    if ($confirm -eq 'yes') {
        Remove-DFCASnippet -DataPath $dataPath -Name $selected.Name
    }
    else {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
    }
}

# ── Action: Edit ──────────────────────────────────────────────
function Invoke-DFCAEdit {
    $yamlFile = Join-Path $dataPath 'snippets.yaml'

    if (-not (Test-Path $yamlFile)) {
        Write-Host "  ❌ No snippets file found at: $yamlFile" -ForegroundColor Red
        return
    }

    $editor = if ($env:EDITOR) { $env:EDITOR }
              elseif (Get-Command code -ErrorAction SilentlyContinue) { 'code' }
              elseif (Get-Command notepad -ErrorAction SilentlyContinue) { 'notepad' }
              else { $null }

    if ($editor) {
        Write-Host "  📝 Opening snippets in $editor..." -ForegroundColor DarkGray
        & $editor $yamlFile
    }
    else {
        Write-Host "  ❌ No editor found. Set `$env:EDITOR or install VS Code." -ForegroundColor Red
    }
}

# ── Action: Default (fzf search) ─────────────────────────────
function Invoke-DFCASearch {
    Show-DFCABanner

    # Step 1: Check dependencies
    Write-Host "  ⏳ Checking dependencies..." -ForegroundColor DarkGray
    if (-not (Test-DFCADependency))    { exit 1 }
    if (-not (Install-DFCAYamlModule)) { exit 1 }
    Write-Host "  ✅ All dependencies satisfied.`n" -ForegroundColor Green

    # Step 2: Load snippets
    Write-Host "  ⏳ Loading snippets..." -ForegroundColor DarkGray
    $snippets = @(Get-DFCASnippets -DataPath $dataPath)
    if ($snippets.Count -eq 0) {
        Write-Host "  ❌ No snippets found. Add some with: dfca --save" -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✅ Loaded $($snippets.Count) snippets.`n" -ForegroundColor Green

    # Step 3: Launch fzf selector
    $selected = Invoke-DFCASelector -Snippets $snippets
    if ($null -eq $selected) { exit 0 }

    Write-Host "`n  ✅ Selected: $($selected.Name)" -ForegroundColor Green
    Write-Host "  📋 Command:  $($selected.Command)`n" -ForegroundColor DarkGray

    # Step 4: Resolve placeholders
    $finalCommand = Resolve-DFCAPlaceholders -Command $selected.Command

    # Step 5: Copy to clipboard
    Copy-DFCAToClipboard -Command $finalCommand
}

# ── Router ────────────────────────────────────────────────────
if ($Save)        { Invoke-DFCASave }
elseif ($List)    { Invoke-DFCAList }
elseif ($Remove)  { Invoke-DFCARemove }
elseif ($Edit)    { Invoke-DFCAEdit }
else              { Invoke-DFCASearch }
