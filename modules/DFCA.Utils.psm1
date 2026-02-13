<#
.SYNOPSIS
    DFCA Utility module — dependency checks and YAML loading.
.DESCRIPTION
    Provides helper functions for verifying external dependencies (fzf, powershell-yaml)
    and loading the snippet library from YAML files.
#>

# ── Public Functions ──────────────────────────────────────────

function Test-DFCADependency {
    <#
    .SYNOPSIS
        Verifies that fzf is available on the system PATH or known install locations.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Refresh PATH from environment in case it was recently updated
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

    $fzf = Get-Command fzf -ErrorAction SilentlyContinue

    # If not found on PATH, check known install locations
    if (-not $fzf) {
        $knownPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\fzf\fzf.exe"
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links\fzf.exe"
            "$env:ProgramFiles\fzf\fzf.exe"
            "$env:USERPROFILE\scoop\shims\fzf.exe"
            "$env:ChocolateyInstall\bin\fzf.exe"
        )

        foreach ($path in $knownPaths) {
            if (Test-Path $path) {
                $fzfDir = Split-Path $path -Parent
                $env:Path += ";$fzfDir"
                $fzf = Get-Command fzf -ErrorAction SilentlyContinue
                break
            }
        }
    }

    if (-not $fzf) {
        Write-Error @"
[DFCA] fzf is not installed or not on your PATH.

  Install it with:
    winget install junegunn.fzf      # Windows
    brew install fzf                 # macOS
    sudo apt install fzf             # Debian/Ubuntu

"@
        return $false
    }

    Write-Verbose "[DFCA] fzf found at: $($fzf.Source)"
    return $true
}

function Install-DFCAYamlModule {
    <#
    .SYNOPSIS
        Ensures the powershell-yaml module is available; installs it if missing.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Get-Module -ListAvailable -Name powershell-yaml) {
        Write-Verbose "[DFCA] powershell-yaml module is already installed."
        Import-Module powershell-yaml -ErrorAction Stop
        return $true
    }

    Write-Host "[DFCA] Installing powershell-yaml module..." -ForegroundColor Yellow
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module powershell-yaml -ErrorAction Stop
        Write-Host "[DFCA] powershell-yaml installed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "[DFCA] Failed to install powershell-yaml: $_"
        return $false
    }
}

function Get-DFCASnippets {
    <#
    .SYNOPSIS
        Loads and parses all YAML snippet files from the data directory.
    .PARAMETER DataPath
        Path to the directory containing YAML snippet files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataPath
    )

    if (-not (Test-Path $DataPath)) {
        Write-Error "[DFCA] Data directory not found: $DataPath"
        return @()
    }

    $yamlFiles = @(Get-ChildItem -Path $DataPath -Filter "*.yaml" -File -ErrorAction SilentlyContinue)
    if ($yamlFiles.Count -eq 0) {
        Write-Error "[DFCA] No .yaml files found in: $DataPath"
        return @()
    }

    $allSnippets = [System.Collections.ArrayList]::new()

    foreach ($file in $yamlFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            $parsed  = ConvertFrom-Yaml -Yaml $content -ErrorAction Stop

            # ConvertFrom-Yaml returns a generic List — enumerate it
            foreach ($item in $parsed) {
                # Items are OrderedDictionaries — use bracket notation
                $cat  = [string]($item['category'])
                $nm   = [string]($item['name'])
                $cmd  = [string]($item['command'])
                $desc = [string]($item['description'])
                $tgs  = $item['tags']
                $tagStr = if ($tgs -is [System.Collections.IEnumerable] -and $tgs -isnot [string]) {
                    ($tgs | ForEach-Object { [string]$_ }) -join ', '
                } else {
                    [string]$tgs
                }

                $snippet = [PSCustomObject]@{
                    Category    = if ($cat)  { $cat }  else { 'Uncategorized' }
                    Name        = if ($nm)   { $nm }   else { 'Unnamed' }
                    Command     = if ($cmd)  { $cmd }  else { '' }
                    Description = if ($desc) { $desc } else { '' }
                    Tags        = $tagStr
                    Source      = $file.Name
                }
                [void]$allSnippets.Add($snippet)
            }

            Write-Verbose "[DFCA] Loaded snippets from $($file.Name)"
        }
        catch {
            Write-Warning "[DFCA] Failed to parse $($file.Name): $_"
        }
    }

    Write-Verbose "[DFCA] Total snippets loaded: $($allSnippets.Count)"
    return $allSnippets.ToArray()
}

# ── Module Export ─────────────────────────────────────────────
Export-ModuleMember -Function @(
    'Test-DFCADependency'
    'Install-DFCAYamlModule'
    'Get-DFCASnippets'
)
