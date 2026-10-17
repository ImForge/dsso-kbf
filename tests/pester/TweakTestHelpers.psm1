# Shared helpers for tweak Pester tests. Invokes tweak functions through
# engine/Invoke-Tweak.ps1 in a child powershell.exe - exactly how the Rust
# engine calls them (env vars like DSSO_KBF_TEST_ROOT are inherited).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:EngineDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\engine')).Path

function Invoke-TweakFunction {
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][ValidateSet('Detect', 'Backup', 'Apply', 'Revert', 'Get-Items')][string]$Function,
        [string]$BackupDir,
        [string]$Items
    )
    $invoke = Join-Path $script:EngineDir 'Invoke-Tweak.ps1'
    $tweak = Join-Path $script:EngineDir "tweaks\$TweakId\tweak.ps1"
    $psArgs = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $invoke, '-TweakPath', $tweak, '-Function', $Function
    )
    if ($BackupDir) { $psArgs += @('-BackupDir', $BackupDir) }
    if ($Items) { $psArgs += @('-Items', $Items) }
    $out = & $script:PsExe @psArgs
    if ($LASTEXITCODE -ne 0) { throw "Invoke-Tweak exited $LASTEXITCODE : $($out -join "`n")" }
    $result = ($out -join "`n") | ConvertFrom-Json
    if (-not $result.ok) { throw "$TweakId/$Function failed: $($result.error)" }
    return $result.value
}

function New-TweakTestBackupDir {
    $dir = Join-Path $env:TEMP ('dsso-kbf-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

Export-ModuleMember -Function Invoke-TweakFunction, New-TweakTestBackupDir
