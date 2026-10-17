# Invoke-Tweak.ps1 - the single entry point the Rust engine (and tests) use to
# call one of a tweak's four functions. Always exits 0 with {ok,...} JSON on
# stdout; a non-zero exit means infrastructure failure, not tweak failure.

param(
    [Parameter(Mandatory)][string]$TweakPath,
    [Parameter(Mandatory)][ValidateSet('Detect', 'Backup', 'Apply', 'Revert')][string]$Function,
    [string]$BackupDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

try {
    if ($Function -in @('Backup', 'Revert') -and [string]::IsNullOrEmpty($BackupDir)) {
        throw "$Function requires -BackupDir"
    }
    . $TweakPath
    $value = switch ($Function) {
        'Detect' { Detect }
        'Backup' { Backup -BackupDir $BackupDir }
        'Apply' { Apply }
        'Revert' { Revert -BackupDir $BackupDir }
    }
    Write-Result @{ ok = $true; value = $value }
} catch {
    Write-Result @{ ok = $false; error = $_.Exception.Message }
}
