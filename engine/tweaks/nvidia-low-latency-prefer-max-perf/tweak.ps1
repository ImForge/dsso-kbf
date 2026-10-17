# nvidia-low-latency-prefer-max-perf - sets the global NVIDIA driver profile to
# Low Latency Mode = On (PRERENDERLIMIT = 1) and Power management mode = Prefer
# maximum performance (PREFERRED_PSTATE = 1). These live in NVIDIA's nvdrsdb
# driver-profile store and are only reachable through NVAPI's DRS API, so this
# tweak calls nvapi64.dll directly (nvapi_QueryInterface P/Invoke via Add-Type,
# the same pattern Common.psm1 uses for SystemParametersInfo). No registry
# pokes, no bundled binaries. Setting ids and values come from NVIDIA's
# published NvApiDriverSettings.h; function ids from NVIDIA's nvapi_interface.h
# (github.com/NVIDIA/nvapi). Verified against driver 581.15.
#
# Backup records, per setting, whether it was user-set in the base profile and
# its exact DWORD value; Revert writes that value back, or deletes the setting
# when it was not user-set (restoring the driver default). Apply re-reads both
# settings through a fresh DRS session to prove the write persisted.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$PrerenderLimitId = 0x007BA09E   # PRERENDERLIMIT_ID; NVCP "Low Latency Mode": 0 = app-controlled (Off), 1 = On
$PreferredPstateId = 0x1057EB71  # PREFERRED_PSTATE_ID; 1 = PREFERRED_PSTATE_PREFER_MAX, 5 = OPTIMAL_POWER (default)
$TargetValues = @{ ([uint32]$PrerenderLimitId) = [uint32]1; ([uint32]$PreferredPstateId) = [uint32]1 }
# Driver defaults from NvApiDriverSettings.h, used only to judge the effective
# state when a setting is absent from the base profile.
$DefaultValues = @{ ([uint32]$PrerenderLimitId) = [uint32]0; ([uint32]$PreferredPstateId) = [uint32]5 }
$BackupFileName = 'nvdrs.json'

$NvDrsSource = @'
using System;
using System.Runtime.InteropServices;

namespace DssoKbf {
    // Minimal NVAPI DRS interop: read/write/delete DWORD settings on the GLOBAL
    // base profile. Function ids are from NVIDIA's nvapi_interface.h; every
    // operation uses a fresh session with LoadSettings so reads always reflect
    // the persisted store.
    public static class NvDrs {
        [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr QueryInterface(uint id);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int VoidFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SessionOutFn(out IntPtr handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SessionFn(IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BaseProfileFn(IntPtr session, out IntPtr profile);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GetSettingFn(IntPtr session, IntPtr profile, uint settingId, ref NVDRS_SETTING setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetSettingFn(IntPtr session, IntPtr profile, ref NVDRS_SETTING setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DeleteSettingFn(IntPtr session, IntPtr profile, uint settingId);

        private const uint IdInitialize = 0x0150E828u;
        private const uint IdDrsCreateSession = 0x0694D52Eu;
        private const uint IdDrsDestroySession = 0xDAD9CFF8u;
        private const uint IdDrsLoadSettings = 0x375DBD6Bu;
        private const uint IdDrsSaveSettings = 0xFCBC7E14u;
        private const uint IdDrsGetBaseProfile = 0xDA8466A0u;
        private const uint IdDrsGetSetting = 0x73BF8338u;
        private const uint IdDrsSetSetting = 0x577DD202u;
        private const uint IdDrsDeleteProfileSetting = 0xE4A26362u;

        public const int StatusOk = 0;
        public const int StatusSettingNotFound = -160; // NVAPI_SETTING_NOT_FOUND

        // NVDRS_SETTING_V1. The two unions (predefined/current value) are a
        // DWORD overlaying max(NvAPI_UnicodeString, NVDRS_BINARY_SETTING) =
        // 4100 bytes, modelled as the DWORD plus 4096 bytes of padding.
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 4)]
        public struct NVDRS_SETTING {
            public uint version;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string settingName;
            public uint settingId;
            public uint settingType;      // 0 = NVDRS_DWORD_TYPE
            public uint settingLocation;  // 0 = NVDRS_CURRENT_PROFILE_LOCATION
            public uint isCurrentPredefined;
            public uint isPredefinedValid;
            public uint u32PredefinedValue;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4096)] public byte[] predefinedPad;
            public uint u32CurrentValue;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4096)] public byte[] currentPad;
        }

        private static T GetFn<T>(uint id) where T : class {
            IntPtr p = QueryInterface(id);
            if (p == IntPtr.Zero) throw new InvalidOperationException("nvapi: function 0x" + id.ToString("X8") + " not exported by this driver");
            return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
        }

        private static void Check(int status, string what) {
            if (status != StatusOk) throw new InvalidOperationException("nvapi: " + what + " failed with status " + status);
        }

        private static uint SettingVersion() {
            return (uint)Marshal.SizeOf(typeof(NVDRS_SETTING)) | 0x10000u;
        }

        private delegate int SessionOp(IntPtr session, IntPtr profile);

        private static int WithBaseProfile(SessionOp op) {
            Check(GetFn<VoidFn>(IdInitialize)(), "Initialize");
            IntPtr session;
            Check(GetFn<SessionOutFn>(IdDrsCreateSession)(out session), "DRS_CreateSession");
            try {
                Check(GetFn<SessionFn>(IdDrsLoadSettings)(session), "DRS_LoadSettings");
                IntPtr profile;
                Check(GetFn<BaseProfileFn>(IdDrsGetBaseProfile)(session, out profile), "DRS_GetBaseProfile");
                return op(session, profile);
            } finally {
                GetFn<SessionFn>(IdDrsDestroySession)(session);
            }
        }

        // Returns [found(0/1), userSet(0/1), value]. found = present in the base
        // profile; userSet = present and not just the predefined default.
        public static long[] ReadSetting(uint settingId) {
            long[] result = new long[3];
            WithBaseProfile(delegate(IntPtr session, IntPtr profile) {
                NVDRS_SETTING s = new NVDRS_SETTING();
                s.version = SettingVersion();
                int status = GetFn<GetSettingFn>(IdDrsGetSetting)(session, profile, settingId, ref s);
                if (status == StatusSettingNotFound) { result[0] = 0; result[1] = 0; result[2] = 0; return StatusOk; }
                Check(status, "DRS_GetSetting(0x" + settingId.ToString("X8") + ")");
                result[0] = 1;
                result[1] = (s.isCurrentPredefined == 0) ? 1 : 0;
                result[2] = s.u32CurrentValue;
                return StatusOk;
            });
            return result;
        }

        public static void WriteSetting(uint settingId, uint value) {
            WithBaseProfile(delegate(IntPtr session, IntPtr profile) {
                NVDRS_SETTING s = new NVDRS_SETTING();
                s.version = SettingVersion();
                s.settingId = settingId;
                s.settingType = 0; // NVDRS_DWORD_TYPE
                s.u32CurrentValue = value;
                Check(GetFn<SetSettingFn>(IdDrsSetSetting)(session, profile, ref s), "DRS_SetSetting(0x" + settingId.ToString("X8") + ")");
                Check(GetFn<SessionFn>(IdDrsSaveSettings)(session), "DRS_SaveSettings");
                return StatusOk;
            });
        }

        public static void DeleteSetting(uint settingId) {
            WithBaseProfile(delegate(IntPtr session, IntPtr profile) {
                int status = GetFn<DeleteSettingFn>(IdDrsDeleteProfileSetting)(session, profile, settingId);
                if (status != StatusSettingNotFound) { // already absent is fine
                    Check(status, "DRS_DeleteProfileSetting(0x" + settingId.ToString("X8") + ")");
                }
                Check(GetFn<SessionFn>(IdDrsSaveSettings)(session), "DRS_SaveSettings");
                return StatusOk;
            });
        }
    }
}
'@

function Initialize-NvDrs {
    # Compiles the interop type once per process. Throws when nvapi64.dll is
    # missing (no NVIDIA driver) - callers decide whether that is fatal.
    if (-not ('DssoKbf.NvDrs' -as [type])) {
        Add-Type -TypeDefinition $NvDrsSource
    }
}

function Get-NvDrsSettingState {
    # @{ found; userSet; value } for one base-profile setting, read through a
    # fresh DRS session so it reflects the persisted store.
    param([Parameter(Mandatory)][uint32]$SettingId)
    Initialize-NvDrs
    $r = [DssoKbf.NvDrs]::ReadSetting($SettingId)
    return @{ found = ($r[0] -eq 1); userSet = ($r[1] -eq 1); value = [uint32]$r[2] }
}

function Detect {
    try {
        $matches2 = 0
        foreach ($id in @([uint32]$PrerenderLimitId, [uint32]$PreferredPstateId)) {
            $state = Get-NvDrsSettingState -SettingId $id
            $effective = if ($state.found) { $state.value } else { $DefaultValues[$id] }
            if ($effective -eq $TargetValues[$id]) { $matches2++ }
        }
        switch ($matches2) {
            2 { return 'applied' }
            0 { return 'not-applied' }
            default { return 'partial' }
        }
    } catch {
        # No NVIDIA driver / NVAPI unavailable: we cannot read, so say so.
        return 'unknown'
    }
}

function Backup {
    param($BackupDir)
    Initialize-NvDrs
    $entries = @()
    foreach ($id in @([uint32]$PrerenderLimitId, [uint32]$PreferredPstateId)) {
        $state = Get-NvDrsSettingState -SettingId $id
        $entries += [pscustomobject][ordered]@{
            settingId = [int64]$id
            userSet   = [bool]$state.userSet
            value     = [int64]$state.value
        }
    }
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $file = Join-Path $BackupDir $BackupFileName
    ConvertTo-Json -InputObject $entries -Depth 5 | Set-Content -Path $file -Encoding UTF8
    @($file)
}

function Apply {
    Initialize-NvDrs
    foreach ($id in @([uint32]$PrerenderLimitId, [uint32]$PreferredPstateId)) {
        [DssoKbf.NvDrs]::WriteSetting($id, $TargetValues[$id])
        # Verify through a fresh session that the write persisted.
        $state = Get-NvDrsSettingState -SettingId $id
        if (-not $state.found -or $state.value -ne $TargetValues[$id]) {
            throw ("nvapi write of setting 0x{0:X8} did not persist (read back: found={1} value={2})" -f $id, $state.found, $state.value)
        }
    }
    return $true
}

function Revert {
    param($BackupDir)
    Initialize-NvDrs
    $entries = Get-Content -Path (Join-Path $BackupDir $BackupFileName) -Raw | ConvertFrom-Json
    foreach ($e in @($entries)) {
        $id = [uint32]$e.settingId
        if ($e.userSet) {
            [DssoKbf.NvDrs]::WriteSetting($id, [uint32]$e.value)
            $state = Get-NvDrsSettingState -SettingId $id
            if (-not $state.found -or $state.value -ne [uint32]$e.value) {
                throw ("revert of setting 0x{0:X8} did not persist (read back: found={1} value={2})" -f $id, $state.found, $state.value)
            }
        } else {
            # Was not user-set before: remove it so the driver default applies again.
            [DssoKbf.NvDrs]::DeleteSetting($id)
            $state = Get-NvDrsSettingState -SettingId $id
            if ($state.userSet) {
                throw ("revert: setting 0x{0:X8} is still user-set after delete" -f $id)
            }
        }
    }
    return $true
}
