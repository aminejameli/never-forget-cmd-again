# DFCA Launcher - Compatible with Windows PowerShell 5.1 and PowerShell Core 7+
# This file intentionally has NO Unicode and NO param block.
# Raw $args are passed through so pwsh 7 can parse --save, -c, etc. correctly.

$mainScript = Join-Path $PSScriptRoot 'dfca-main.ps1'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) {
        Write-Host ""
        Write-Host "  [DFCA] PowerShell Core 7+ (pwsh) is required but not found." -ForegroundColor Red
        Write-Host "  Install it:  winget install Microsoft.PowerShell" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    $pwshArgs = @('-NoProfile', '-File', $mainScript) + $args
    & pwsh @pwshArgs
    exit $LASTEXITCODE
}

# Already in pwsh 7+ - forward all args to the main script
& $mainScript @args
