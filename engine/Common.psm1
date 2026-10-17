# Common.psm1 - shared helpers for the dsso-kbf tweak engine.
# PowerShell 5.1 compatible. Every engine script imports this.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SelectedItemIds {
    # Parses DSSO_KBF_ITEMS for list-driven tweaks. Returns $null when unset
    # (meaning: no selection was made).
    if ([string]::IsNullOrEmpty($env:DSSO_KBF_ITEMS)) { return $null }
    return @($env:DSSO_KBF_ITEMS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

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

function Resolve-TweakPath {
    # Redirects registry paths into a throwaway hive when DSSO_KBF_TEST_ROOT is
    # set (Pester unit tests), e.g. HKCU:\Software\X -> <root>\HKCU\Software\X.
    param([Parameter(Mandatory)][string]$Path)
    $root = $env:DSSO_KBF_TEST_ROOT
    if ([string]::IsNullOrEmpty($root)) { return $Path }
    return (Join-Path $root ($Path -replace ':', ''))
}

function Test-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
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
    # Exports a whole registry key (reg.exe path syntax, e.g.
    # HKCU\System\GameConfigStore) into $BackupDir\$FileName; returns the path.
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

function Backup-RegValues {
    # Saves individual registry values (with existence + type) to a JSON file so
    # Restore-RegValues can put back the EXACT prior state, including deleting
    # values that did not exist. $Entries: array of @{ Path = ...; Name = ... }.
    param(
        [Parameter(Mandatory)][array]$Entries,
        [Parameter(Mandatory)][string]$File
    )
    $saved = @()
    foreach ($e in $Entries) {
        $exists = Test-RegValue -Path $e.Path -Name $e.Name
        $entry = [ordered]@{ path = $e.Path; name = $e.Name; exists = $exists; type = $null; value = $null }
        if ($exists) {
            $key = Get-Item -Path $e.Path
            $entry.type = [string]$key.GetValueKind($e.Name)
            $entry.value = Get-RegValue $e.Path $e.Name
        }
        $saved += [pscustomobject]$entry
    }
    $dir = Split-Path $File -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ConvertTo-Json -InputObject $saved -Depth 5 | Set-Content -Path $File -Encoding UTF8
    return $File
}

function Restore-RegValues {
    # Restores values saved by Backup-RegValues: sets what existed (same type),
    # deletes what did not.
    param([Parameter(Mandatory)][string]$File)
    $entries = Get-Content -Path $File -Raw | ConvertFrom-Json
    foreach ($e in @($entries)) {
        if ($e.exists) {
            $value = $e.value
            if ($e.type -eq 'Binary') { $value = [byte[]]@($e.value) }
            if ($e.type -eq 'MultiString') { $value = [string[]]@($e.value) }
            Set-RegValue -Path $e.path -Name $e.name -Value $value -Type $e.type
        } elseif (Test-RegValue -Path $e.path -Name $e.name) {
            Remove-ItemProperty -Path $e.path -Name $e.name -Force
        }
    }
    return $true
}

function Get-ActivePowerSchemeGuid {
    $line = (& powercfg.exe /getactivescheme) -join ' '
    if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return $Matches[1]
    }
    throw 'cannot parse active power scheme from powercfg output'
}

function Get-PowerSettingAcIndex {
    # NOTE: parses English powercfg output ("Current AC Power Setting Index");
    # known limitation on localized Windows.
    param(
        [Parameter(Mandatory)][string]$SubGroup,
        [Parameter(Mandatory)][string]$Setting
    )
    $out = (& powercfg.exe /q SCHEME_CURRENT $SubGroup $Setting) -join "`n"
    if ($out -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
        return [convert]::ToInt32($Matches[1], 16)
    }
    throw "cannot read power setting $SubGroup/$Setting"
}

function Set-PowerSettingAcIndex {
    param(
        [Parameter(Mandatory)][string]$SubGroup,
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][int]$Value
    )
    & powercfg.exe /setacvalueindex SCHEME_CURRENT $SubGroup $Setting $Value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setacvalueindex $SubGroup/$Setting failed (exit $LASTEXITCODE)" }
    & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed (exit $LASTEXITCODE)" }
}

function Update-MouseSettings {
    # Re-reads the mouse acceleration values and broadcasts SPI_SETMOUSE so the
    # change applies immediately instead of at next sign-in.
    if (-not ('DssoKbf.MouseNative' -as [type])) {
        Add-Type -Namespace 'DssoKbf' -Name 'MouseNative' -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
'@
    }
    $mousePath = 'HKCU:\Control Panel\Mouse'
    $m = @(
        [int](Get-RegValue $mousePath 'MouseThreshold1' '0'),
        [int](Get-RegValue $mousePath 'MouseThreshold2' '0'),
        [int](Get-RegValue $mousePath 'MouseSpeed' '0')
    )
    # SPI_SETMOUSE = 0x0004; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 0x03
    [void][DssoKbf.MouseNative]::SystemParametersInfo(0x0004, 0, $m, 0x03)
}

Export-ModuleMember -Function Get-SelectedItemIds, Test-Admin, Write-Result, Resolve-TweakPath, Test-RegValue, `
    Get-RegValue, Set-RegValue, Backup-RegKey, Backup-RegValues, Restore-RegValues, `
    Get-ActivePowerSchemeGuid, Get-PowerSettingAcIndex, Set-PowerSettingAcIndex, Update-MouseSettings
