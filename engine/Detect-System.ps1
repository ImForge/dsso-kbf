# Detect-System.ps1 — emits SystemProfile JSON (schema in CLAUDE.md) to stdout.
# Read-only: never changes system state. PowerShell 5.1 compatible.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-OsBlock {
    $nt = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{
        build   = [int](Get-RegValue $nt 'CurrentBuildNumber' '0')
        version = [string](Get-RegValue $nt 'DisplayVersion' '')
        edition = [string](Get-RegValue $nt 'EditionID' '')
    }
}

function Get-CpuBlock {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $vendor = switch -Wildcard ($cpu.Manufacturer) {
        '*Intel*' { 'intel' }
        '*AMD*'   { 'amd' }
        default   { 'unknown' }
    }
    $cores = [int]$cpu.NumberOfCores
    $threads = [int]$cpu.NumberOfLogicalProcessors
    # Heuristic: hybrid Intel parts mix HT P-cores with non-HT E-cores, so the
    # thread count sits strictly between cores and 2*cores.
    $hybrid = ($vendor -eq 'intel') -and ($threads -gt $cores) -and ($threads -lt (2 * $cores))
    [ordered]@{
        vendor  = $vendor
        name    = ([string]$cpu.Name).Trim()
        cores   = $cores
        threads = $threads
        hybrid  = $hybrid
    }
}

function Get-GpuVendor {
    param([string]$PnpId, [string]$Name)
    if ($PnpId -match 'VEN_10DE' -or $Name -match 'NVIDIA') { return 'nvidia' }
    if ($PnpId -match 'VEN_1002|VEN_1022' -or $Name -match 'AMD|Radeon') { return 'amd' }
    if ($PnpId -match 'VEN_8086' -or $Name -match 'Intel') { return 'intel' }
    return 'unknown'
}

function Get-GpuVramMb {
    # Win32_VideoController.AdapterRAM is a uint32 and caps at 4 GB; the display
    # class key stores the real size in HardwareInformation.qwMemorySize.
    param([string]$DriverDesc)
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($sub in Get-ChildItem $classKey -ErrorAction SilentlyContinue) {
        if ($sub.PSChildName -notmatch '^\d{4}$') { continue }
        $desc = Get-RegValue $sub.PSPath 'DriverDesc' ''
        if ($desc -eq $DriverDesc) {
            $qw = Get-RegValue $sub.PSPath 'HardwareInformation.qwMemorySize' $null
            if ($null -ne $qw) { return [long]($qw / 1MB) }
        }
    }
    return $null
}

function Get-GpuBlocks {
    $list = @()
    $controllers = @(Get-CimInstance Win32_VideoController | Where-Object {
            $_.PNPDeviceID -like 'PCI\*' -and $_.Name -notmatch 'Microsoft Basic Display'
        })
    foreach ($gpu in $controllers) {
        $vendor = Get-GpuVendor -PnpId $gpu.PNPDeviceID -Name $gpu.Name
        $driver = [string]$gpu.DriverVersion
        if ($vendor -eq 'nvidia') {
            # Windows stores e.g. 32.0.15.6603; the NVIDIA version is the last
            # five digits: 56603 -> 566.03.
            $digits = $driver -replace '\.', ''
            if ($digits.Length -ge 5) {
                $last5 = $digits.Substring($digits.Length - 5)
                $driver = '{0}.{1}' -f $last5.Substring(0, 3), $last5.Substring(3)
            }
        }
        $vramMb = Get-GpuVramMb -DriverDesc $gpu.Name
        if ($null -eq $vramMb) {
            $vramMb = if ($gpu.AdapterRAM) { [long]($gpu.AdapterRAM / 1MB) } else { 0 }
        }
        $list += [ordered]@{
            vendor  = $vendor
            name    = [string]$gpu.Name
            driver  = $driver
            vram_mb = $vramMb
        }
    }
    return , $list
}

function Get-StorageBlocks {
    $list = @()
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
        $partitions = @(Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })
        foreach ($p in $partitions) {
            $disk = $disks | Where-Object { $_.DeviceId -eq [string]$p.DiskNumber } | Select-Object -First 1
            $type = 'unknown'
            if ($disk) {
                if ([string]$disk.BusType -eq 'NVMe') { $type = 'nvme' }
                elseif ([string]$disk.MediaType -eq 'SSD') { $type = 'ssd' }
                elseif ([string]$disk.MediaType -eq 'HDD') { $type = 'hdd' }
            }
            $list += [ordered]@{ drive = ('{0}:' -f $p.DriveLetter); type = $type }
        }
    } catch {
        foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
            $list += [ordered]@{ drive = [string]$d.DeviceID; type = 'unknown' }
        }
    }
    return , $list
}

function Get-FormFactor {
    # Chassis types that mean portable: laptop/notebook/subnotebook/handheld/
    # tablet/convertible/detachable.
    $portable = 8, 9, 10, 11, 14, 30, 31, 32
    try {
        $types = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
        foreach ($t in $types) {
            if ($portable -contains [int]$t) { return 'laptop' }
        }
    } catch { }
    if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { return 'laptop' }
    return 'desktop'
}

function Get-StateBlock {
    $vbs = $false
    $hvci = $false
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
        $vbs = [int]$dg.VirtualizationBasedSecurityStatus -eq 2
        $hvci = @($dg.SecurityServicesRunning) -contains 2
    } catch { }

    $powerPlan = 'Unknown'
    try {
        $active = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -Filter 'IsActive = TRUE'
        if ($active) { $powerPlan = [string]$active.ElementName }
    } catch { }
    if ($powerPlan -eq 'Unknown') {
        # The power CIM namespace is unavailable on Modern Standby machines;
        # powercfg prints: Power Scheme GUID: <guid>  (<name>)
        try {
            $line = (& powercfg.exe /getactivescheme) -join ' '
            if ($line -match '\(([^)]+)\)\s*$') { $powerPlan = $Matches[1] }
        } catch { }
    }

    [ordered]@{
        vbs_enabled  = $vbs
        hvci_enabled = $hvci
        hags_enabled = ([int](Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 0)) -eq 2
        game_mode    = ([int](Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1)) -eq 1
        game_dvr     = ([int](Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1)) -eq 1
        power_plan   = $powerPlan
        fso_global   = ([int](Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0)) -ne 2
        mouse_accel  = ([string](Get-RegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '1')) -ne '0'
    }
}

$systemProfile = [ordered]@{
    os          = Get-OsBlock
    cpu         = Get-CpuBlock
    gpu         = Get-GpuBlocks
    ram_mb      = [long]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    storage     = Get-StorageBlocks
    form_factor = Get-FormFactor
    state       = Get-StateBlock
}

Write-Output (ConvertTo-Json -InputObject $systemProfile -Depth 6)
