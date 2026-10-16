# Common.psm1 — shared helpers for the dsso-kbf tweak engine.
# PowerShell 5.1 compatible. Every engine script imports this.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Result {
    # The only way engine scripts write to stdout: one compact JSON object.
    param([Parameter(Mandatory)] $Data)
    Write-Output (ConvertTo-Json -InputObject $Data -Depth 10 -Compress)
}

function Get-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $Default
    }
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')]
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

function Backup-RegKey {
    # Exports a registry key (reg.exe path syntax, e.g. HKCU\System\GameConfigStore)
    # into $BackupDir\$FileName and returns the file path.
    param(
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][string]$FileName
    )
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $dest = Join-Path $BackupDir $FileName
    $null = & reg.exe export $KeyPath $dest /y 2>&1
    if ($LASTEXITCODE -ne 0) { throw "reg.exe export failed for $KeyPath (exit $LASTEXITCODE)" }
    return $dest
}

Export-ModuleMember -Function Test-Admin, Write-Result, Get-RegValue, Set-RegValue, Backup-RegKey
