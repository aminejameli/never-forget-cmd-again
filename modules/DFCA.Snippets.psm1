<#
.SYNOPSIS
    DFCA Snippets module — CRUD operations for the snippet YAML library.
.DESCRIPTION
    Provides functions for saving, removing, and listing snippets in the
    DFCA YAML data files.
#>

# ── Save ──────────────────────────────────────────────────────

function Save-DFCASnippet {
    <#
    .SYNOPSIS
        Appends a new snippet to the snippets.yaml file.
    .PARAMETER DataPath
        Path to the data directory containing YAML files.
    .PARAMETER Name
        Human-readable name of the snippet.
    .PARAMETER Command
        The command string to save.
    .PARAMETER Category
        Category grouping (default: "general").
    .PARAMETER Tags
        Comma-separated tags string.
    .PARAMETER Description
        What the command does.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataPath,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [string]$Category = 'general',
        [string]$Tags = '',
        [string]$Description = ''
    )

    $yamlFile = Join-Path $DataPath 'snippets.yaml'

    # Ensure data directory exists
    if (-not (Test-Path $DataPath)) {
        New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
    }

    # Ensure YAML file exists with header
    if (-not (Test-Path $yamlFile)) {
        $header = @"
# ╔══════════════════════════════════════════════════════════════╗
# ║  DFCA — Don't Forget Commands Again                        ║
# ║  Add your commands below following this structure           ║
# ╚══════════════════════════════════════════════════════════════╝

"@
        Set-Content -Path $yamlFile -Value $header -Encoding utf8
    }

    # Check for duplicate names
    $existingContent = Get-Content -Path $yamlFile -Raw -ErrorAction SilentlyContinue
    if ($existingContent -and $existingContent -match "name:\s*[`"']?$([regex]::Escape($Name))[`"']?\s*$") {
        Write-Host ""
        Write-Host "  ⚠  A snippet named '$Name' already exists!" -ForegroundColor Yellow
        Write-Host "     Use a different name or remove the existing one first." -ForegroundColor DarkGray
        Write-Host ""
        return $false
    }

    # Build the tag list
    $tagList = if ([string]::IsNullOrWhiteSpace($Tags)) {
        '[]'
    } else {
        $tagItems = ($Tags -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        '[' + ($tagItems -join ', ') + ']'
    }

    # Escape command for YAML (wrap in double quotes, escape inner quotes)
    $escapedCommand = $Command -replace '"', '\"'
    $escapedDesc    = if ([string]::IsNullOrWhiteSpace($Description)) { $Name } else { $Description }

    # Build YAML block
    $yamlBlock = @"

- category: $($Category.ToLower())
  name: $Name
  command: "$escapedCommand"
  description: "$escapedDesc"
  tags: $tagList
"@

    # Append to file
    Add-Content -Path $yamlFile -Value $yamlBlock -Encoding utf8

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     ✅ Snippet saved!                ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Name     : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$Name" -ForegroundColor Cyan
    Write-Host "  Category : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$Category" -ForegroundColor Yellow
    Write-Host "  Command  : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$Command" -ForegroundColor White
    Write-Host "  Tags     : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$tagList" -ForegroundColor DarkCyan
    Write-Host ""

    return $true
}

# ── Interactive Save ──────────────────────────────────────────

function Invoke-DFCAInteractiveSave {
    <#
    .SYNOPSIS
        Prompts the user for each snippet field interactively.
    .PARAMETER DataPath
        Path to the data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataPath
    )

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║      Save a New Command              ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""

    # Required fields
    Write-Host "  ▸ Command " -NoNewline -ForegroundColor Yellow
    Write-Host "(required): " -NoNewline -ForegroundColor DarkGray
    $cmd = Read-Host
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Write-Host "  ❌ Command is required. Aborting." -ForegroundColor Red
        return
    }

    Write-Host "  ▸ Name " -NoNewline -ForegroundColor Yellow
    Write-Host "(required): " -NoNewline -ForegroundColor DarkGray
    $name = Read-Host
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "  ❌ Name is required. Aborting." -ForegroundColor Red
        return
    }

    # Optional fields
    Write-Host "  ▸ Category " -NoNewline -ForegroundColor Yellow
    Write-Host "(default: general): " -NoNewline -ForegroundColor DarkGray
    $cat = Read-Host
    if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'general' }

    Write-Host "  ▸ Tags " -NoNewline -ForegroundColor Yellow
    Write-Host "(comma-separated): " -NoNewline -ForegroundColor DarkGray
    $tags = Read-Host

    Write-Host "  ▸ Description " -NoNewline -ForegroundColor Yellow
    Write-Host "(optional): " -NoNewline -ForegroundColor DarkGray
    $desc = Read-Host

    Save-DFCASnippet -DataPath $DataPath -Name $name -Command $cmd -Category $cat -Tags $tags -Description $desc
}

# ── List ──────────────────────────────────────────────────────

function Show-DFCASnippetList {
    <#
    .SYNOPSIS
        Prints all snippets in a formatted table.
    .PARAMETER Snippets
        Array of snippet objects from Get-DFCASnippets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$Snippets
    )

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║      DFCA — Snippet Library          ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""

    $idx = 1
    foreach ($s in $Snippets) {
        $num = "$idx".PadLeft(3)
        Write-Host "  $num. " -NoNewline -ForegroundColor DarkGray
        Write-Host "[$($s.Category)] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($s.Name)" -ForegroundColor Cyan
        Write-Host "       $($s.Command)" -ForegroundColor White
        if ($s.Tags -and $s.Tags -ne '') {
            Write-Host "       Tags: $($s.Tags)" -ForegroundColor DarkGray
        }
        Write-Host ""
        $idx++
    }

    Write-Host "  Total: $($Snippets.Count) snippet(s)" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Remove ────────────────────────────────────────────────────

function Remove-DFCASnippet {
    <#
    .SYNOPSIS
        Removes a snippet by name from the YAML file.
    .PARAMETER DataPath
        Path to the data directory.
    .PARAMETER Name
        Name of the snippet to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataPath,
        [Parameter(Mandatory)][string]$Name
    )

    $yamlFile = Join-Path $DataPath 'snippets.yaml'

    if (-not (Test-Path $yamlFile)) {
        Write-Host "  ❌ No snippets file found." -ForegroundColor Red
        return $false
    }

    # Load, filter, and rewrite
    $content = Get-Content -Path $yamlFile -Raw -ErrorAction Stop
    $parsed  = ConvertFrom-Yaml -Yaml $content -ErrorAction Stop

    $filtered = @($parsed | Where-Object { [string]$_['name'] -ne $Name })

    if ($filtered.Count -eq $parsed.Count) {
        Write-Host "  ⚠  No snippet named '$Name' found." -ForegroundColor Yellow
        return $false
    }

    # Rewrite the YAML file
    $header = @"
# ╔══════════════════════════════════════════════════════════════╗
# ║  DFCA — Don't Forget Commands Again                        ║
# ║  Add your commands below following this structure           ║
# ╚══════════════════════════════════════════════════════════════╝

"@
    $newContent = $header

    foreach ($item in $filtered) {
        $cat  = [string]($item['category'])
        $nm   = [string]($item['name'])
        $cmd  = [string]($item['command'])
        $desc = [string]($item['description'])
        $tgs  = $item['tags']
        $tagStr = if ($tgs -is [System.Collections.IEnumerable] -and $tgs -isnot [string]) {
            '[' + (($tgs | ForEach-Object { [string]$_ }) -join ', ') + ']'
        } elseif ($tgs) {
            "[$tgs]"
        } else {
            '[]'
        }

        $escapedCmd = $cmd -replace '"', '\"'

        $newContent += @"

- category: $cat
  name: $nm
  command: "$escapedCmd"
  description: "$desc"
  tags: $tagStr
"@
    }

    Set-Content -Path $yamlFile -Value $newContent -Encoding utf8

    Write-Host ""
    Write-Host "  ✅ Removed snippet: '$Name'" -ForegroundColor Green
    Write-Host "  Remaining: $($filtered.Count) snippet(s)" -ForegroundColor DarkGray
    Write-Host ""

    return $true
}

# ── Module Export ─────────────────────────────────────────────
Export-ModuleMember -Function @(
    'Save-DFCASnippet'
    'Invoke-DFCAInteractiveSave'
    'Show-DFCASnippetList'
    'Remove-DFCASnippet'
)
