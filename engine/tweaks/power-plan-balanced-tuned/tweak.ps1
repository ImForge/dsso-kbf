# power-plan-balanced-tuned - keep Balanced, fix USB selective suspend + PCIe
# link state on AC (laptop only).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$UsbSubGroup = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSetting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$PcieSubGroup = '501a4d13-42af-4429-9fd1-a8218c268e20'
$PcieSetting = 'ee12f906-d277-404b-b6da-e5fa1a576df5'

function Detect {
    $usb = Get-PowerSettingAcIndex -SubGroup $UsbSubGroup -Setting $UsbSetting
    $pcie = Get-PowerSettingAcIndex -SubGroup $PcieSubGroup -Setting $PcieSetting
    if ($usb -eq 0 -and $pcie -eq 0) { return 'applied' }
    if ($usb -ne 0 -and $pcie -ne 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $file = Join-Path $BackupDir 'power-settings.json'
    ConvertTo-Json -InputObject @{
        usb_ac  = (Get-PowerSettingAcIndex -SubGroup $UsbSubGroup -Setting $UsbSetting)
        pcie_ac = (Get-PowerSettingAcIndex -SubGroup $PcieSubGroup -Setting $PcieSetting)
    } | Set-Content -Path $file -Encoding UTF8
    @($file)
}

function Apply {
    Set-PowerSettingAcIndex -SubGroup $UsbSubGroup -Setting $UsbSetting -Value 0
    Set-PowerSettingAcIndex -SubGroup $PcieSubGroup -Setting $PcieSetting -Value 0
    return $true
}

function Revert {
    param($BackupDir)
    $saved = Get-Content -Path (Join-Path $BackupDir 'power-settings.json') -Raw | ConvertFrom-Json
    Set-PowerSettingAcIndex -SubGroup $UsbSubGroup -Setting $UsbSetting -Value ([int]$saved.usb_ac)
    Set-PowerSettingAcIndex -SubGroup $PcieSubGroup -Setting $PcieSetting -Value ([int]$saved.pcie_ac)
    return $true
}
