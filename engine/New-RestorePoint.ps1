# New-RestorePoint.ps1 - try to create a System Restore Point and report what
# happened as JSON: { created, reason }. reason names the actual cause when it
# fails: '24h-skip' (Windows silently skips points within 24 h of the last one)
# or 'protection-off' (System Protection disabled on C:). Never throws.

param([string]$Description = 'dsso-kbf tweak session')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Checkpoint-Computer writes its 24h-skip WARNING through the host, which lands
# on stdout and would corrupt our JSON. The count comparison below detects the
# skip instead.
$WarningPreference = 'SilentlyContinue'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

$before = $null
try { $before = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { }

try {
    Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS `
        -ErrorAction Stop -WarningAction SilentlyContinue
    $after = @()
    try { $after = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { }
    if ($null -ne $before -and $after.Count -le $before.Count) {
        # Checkpoint-Computer "succeeds" but silently skips within 24h
        # (SystemRestorePointCreationFrequency).
        Write-Result @{ created = $false; reason = '24h-skip' }
    } else {
        Write-Result @{ created = $true; reason = 'ok' }
    }
} catch {
    $msg = $_.Exception.Message
    $reason = if ($msg -match '0x80042306|0x80042302|disabled|deaktiv') { 'protection-off' } else { $msg }
    Write-Result @{ created = $false; reason = $reason }
}
