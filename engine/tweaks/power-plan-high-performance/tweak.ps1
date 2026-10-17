# power-plan-high-performance - activate the High performance plan (desktop only).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

function Detect {
    if ((Get-ActivePowerSchemeGuid) -ieq $HighPerfGuid) { return 'applied' }
    return 'not-applied'
}

function Backup {
    param($BackupDir)
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $file = Join-Path $BackupDir 'scheme.json'
    ConvertTo-Json -InputObject @{ active_scheme = (Get-ActivePowerSchemeGuid) } |
        Set-Content -Path $file -Encoding UTF8
    @($file)
}

function Apply {
    & powercfg.exe /setactive $HighPerfGuid | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /setactive failed (exit $LASTEXITCODE) - the High performance plan may not exist on this system"
    }
    return $true
}

function Revert {
    param($BackupDir)
    $saved = Get-Content -Path (Join-Path $BackupDir 'scheme.json') -Raw | ConvertFrom-Json
    & powercfg.exe /setactive $saved.active_scheme | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive $($saved.active_scheme) failed (exit $LASTEXITCODE)" }
    return $true
}
