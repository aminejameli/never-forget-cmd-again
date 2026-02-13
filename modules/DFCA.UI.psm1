<#
.SYNOPSIS
    DFCA UI module — fzf integration, placeholder resolution, and clipboard.
.DESCRIPTION
    Handles the interactive fzf selector with a split-pane preview window,
    prompts the user for {{placeholder}} values, and copies the final command
    to the system clipboard.
#>


# ── Constants ─────────────────────────────────────────────────
$script:Separator = '│'

# ── Public Functions ──────────────────────────────────────────

function Invoke-DFCASelector {
    <#
    .SYNOPSIS
        Presents snippets in fzf with a professional split-pane preview.
    .PARAMETER Snippets
        Array of snippet PSCustomObjects (from Get-DFCASnippets).
    .OUTPUTS
        [PSCustomObject] The selected snippet, or $null if cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Snippets
    )

    if ($Snippets.Count -eq 0) {
        Write-Warning "[DFCA] No snippets to display."
        return $null
    }

    # Build display lines with a hidden index prefix (TAB-delimited for reliability)
    $lines = [System.Collections.Generic.List[string]]::new()
    $sep   = [char]0x2502  # │ for visual display

    for ($i = 0; $i -lt $Snippets.Count; $i++) {
        $s = $Snippets[$i]
        # Format: "IDX\t[Category] Name │ Command"  (TAB separates hidden index)
        $line = "$i`t[$($s.Category)] $($s.Name) $sep $($s.Command)"
        $lines.Add($line)
    }

    # Build a temp file for the preview script so fzf --preview can call it
    $previewScript = New-TemporaryFile
    $previewScript = Rename-Item -Path $previewScript.FullName -NewName ($previewScript.Name + '.ps1') -PassThru

    # The preview script receives the selected line and extracts details
    $previewCode = @'
param($line)
# Split on TAB first to skip the index
$tabParts = $line -split "`t", 2
$display = if ($tabParts.Length -gt 1) { $tabParts[1] } else { $tabParts[0] }

$sep = [char]0x2502   # │
$parts = $display -split [regex]::Escape($sep), 2

$header = $parts[0].Trim()
$cmd    = if ($parts.Length -gt 1) { $parts[1].Trim() } else { '—' }

# Extract category and name from "[Category] Name"
if ($header -match '^\[(.+?)\]\s*(.+)$') {
    $cat  = $Matches[1].Trim()
    $name = $Matches[2].Trim()
} else {
    $cat  = '—'
    $name = $header
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║        DFCA — Command Preview        ║" -ForegroundColor DarkCyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Category : " -NoNewline -ForegroundColor DarkGray
Write-Host "$cat" -ForegroundColor Yellow
Write-Host "  Name     : " -NoNewline -ForegroundColor DarkGray
Write-Host "$name" -ForegroundColor Green
Write-Host ""
Write-Host "  ── Command ──────────────────────────" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  $cmd" -ForegroundColor White
Write-Host ""
'@

    Set-Content -Path $previewScript.FullName -Value $previewCode -Encoding utf8

    # Pipe lines into fzf — TAB delimiter, hide the index column (field 1)
    $previewCmd = "pwsh -NoProfile -File `"$($previewScript.FullName)`" {}"

    try {
        $selected = $lines | fzf `
            --ansi `
            --height=80% `
            --layout=reverse `
            --border=rounded `
            --delimiter="`t" `
            --with-nth='2..' `
            --prompt='🔍 DFCA > ' `
            --header='  ↑↓ Navigate  │  Enter Select  │  Esc Cancel' `
            --header-first `
            --preview=$previewCmd `
            --preview-window='right:50%:wrap:border-left' `
            --color='fg:#c0caf5,bg:#1a1b26,hl:#7aa2f7,fg+:#c0caf5,bg+:#292e42,hl+:#7dcfff,info:#7aa2f7,prompt:#f7768e,pointer:#ff9e64,marker:#9ece6a,spinner:#bb9af7,header:#565f89,border:#3b4261'

        if ([string]::IsNullOrWhiteSpace($selected)) {
            Write-Host "`n[DFCA] Selection cancelled." -ForegroundColor DarkGray
            return $null
        }

        # Extract the index from before the TAB
        $idx = ($selected -split "`t")[0].Trim()

        if ($idx -match '^\d+$') {
            return $Snippets[[int]$idx]
        }
        else {
            Write-Warning "[DFCA] Could not parse selection: '$selected'"
            return $null
        }
    }
    catch {
        Write-Error "[DFCA] fzf encountered an error: $_"
        return $null
    }
    finally {
        Remove-Item -Path $previewScript.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-DFCAPlaceholders {
    <#
    .SYNOPSIS
        Finds all {{placeholder}} tokens in a command and prompts the user for values.
    .PARAMETER Command
        The raw command string containing {{placeholder}} tokens.
    .OUTPUTS
        [string] The command with all placeholders replaced.
    .EXAMPLE
        $resolved = Resolve-DFCAPlaceholders -Command "docker run -it {{image}}"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $pattern = '\{\{(\w+)\}\}'
    $matches = [regex]::Matches($Command, $pattern)

    if ($matches.Count -eq 0) {
        Write-Verbose "[DFCA] No placeholders found in command."
        return $Command
    }

    # Deduplicate placeholders while preserving order
    $seen   = [System.Collections.Generic.HashSet[string]]::new()
    $unique = [System.Collections.Generic.List[string]]::new()

    foreach ($m in $matches) {
        $placeholder = $m.Groups[1].Value
        if ($seen.Add($placeholder)) {
            $unique.Add($placeholder)
        }
    }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║      Fill in the placeholders        ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""

    $result = $Command
    foreach ($placeholder in $unique) {
        $promptText = "  ▸ {{$placeholder}}: "
        Write-Host $promptText -NoNewline -ForegroundColor Yellow
        $value = Read-Host

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Warning "  ⚠ Empty value for {{$placeholder}}, keeping placeholder."
        }
        else {
            $result = $result -replace [regex]::Escape("{{$placeholder}}"), $value
        }
    }

    return $result
}

function Copy-DFCAToClipboard {
    <#
    .SYNOPSIS
        Copies the final assembled command to the system clipboard and confirms.
    .PARAMETER Command
        The fully-resolved command string.
    .EXAMPLE
        Copy-DFCAToClipboard -Command "docker run -it --rm ubuntu /bin/bash"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    try {
        Set-Clipboard -Value $Command -ErrorAction Stop

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║     ✅ Copied to clipboard!          ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "  $Command" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Warning "[DFCA] Could not copy to clipboard: $_"
        Write-Host ""
        Write-Host "  ── Your command ─────────────────────" -ForegroundColor DarkCyan
        Write-Host "  $Command" -ForegroundColor White
        Write-Host ""
    }
}

# ── Module Export ─────────────────────────────────────────────
Export-ModuleMember -Function @(
    'Invoke-DFCASelector'
    'Resolve-DFCAPlaceholders'
    'Copy-DFCAToClipboard'
)
