# Test the extracted release archive, then hide its driver and require failure.
# Registry changes are temporary; the original archive is never changed.
param([Parameter(Mandatory = $true)][string]$Package)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run this probe on Windows.' }
$Root = Split-Path $PSScriptRoot -Parent
$Archive = (Resolve-Path $Package).Path
$Name = [IO.Path]::GetFileName($Archive) -replace '\.zip$', ''
if ($Name -notmatch '-windows-(x86_64|aarch64)$') { throw 'Expected a Windows ZIP package.' }
$Cpu = $Matches[1]
$NativeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if (($Cpu -eq 'aarch64' -and $NativeArchitecture -ne 'Arm64') -or
    ($Cpu -eq 'x86_64' -and $NativeArchitecture -ne 'X64')) { throw 'Use a native runner for this package.' }
$ExpectedHash = ((Get-Content "$Archive.sha256" -Raw) -split '\s+')[0]
if ((Get-FileHash $Archive -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Archive SHA-256 mismatch.' }
$Check = Join-Path $Root ('check/windows-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $Check | Out-Null
Expand-Archive -LiteralPath $Archive -DestinationPath $Check
$Lib = Join-Path $Check "$Name/lib"
Copy-Item "$Root/dist/probe-windows-$Cpu.exe" "$Lib/probe.exe"
$Manifest = (Resolve-Path "$Lib/lvp_icd.$Cpu.json").Path
$Driver = Join-Path $Lib 'vulkan_lvp.dll'
$DriverKey = 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers'
$Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$Registered = $false
$PreviousValue = $null
$CreatedKey = $false
$PreviousPath = $env:PATH
$PreviousDriverFiles = $env:VK_DRIVER_FILES
try {
    # Installed compiler/MSYS2 DLLs must not mask a missing runtime dependency.
    $env:PATH = "$env:SystemRoot\System32"
    # As Valle uses it: no loader, manifest, environment or registry, elevated or not.
    Write-Host "=== Its driver directly, without the loader (elevated: $Admin)"
    # LoadLibrary takes backslashes only.
    & "$Lib/probe.exe" --direct ([IO.Path]::GetFullPath($Driver))
    if ($LASTEXITCODE -ne 0) { throw 'Direct Vulkan compute probe failed.' }
    # Elevated loaders ignore VK_DRIVER_FILES; ordinary processes use the explicit path.
    if ($Admin) {
        $CreatedKey = !(Test-Path $DriverKey)
        if ($CreatedKey) { New-Item -Path $DriverKey -Force | Out-Null }
        # A fresh extraction has no registered value. Get-ItemPropertyValue throws
        # for missing names even with SilentlyContinue; RegistryKey.GetValue returns null.
        $RegistryKey = Get-Item -LiteralPath $DriverKey
        try { $PreviousValue = $RegistryKey.GetValue($Manifest, $null) }
        finally { $RegistryKey.Close() }
        New-ItemProperty -Path $DriverKey -Name $Manifest -PropertyType DWord -Value 0 -Force | Out-Null
        $Registered = $true
    }
    $env:VK_DRIVER_FILES = $Manifest
    Write-Host '=== With the packaged loader and driver'
    & "$Lib/probe.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Packaged Vulkan compute probe failed.' }
    Write-Host '=== Without the packaged driver (must fail)'
    Move-Item $Driver "$Driver.disabled"
    & "$Lib/probe.exe"
    if ($LASTEXITCODE -eq 0) { throw 'Probe succeeded without the packaged driver.' }
    Write-Host 'PASS: packaged driver computes correctly, directly too; removing it causes failure.'
} finally {
    if (Test-Path "$Driver.disabled") { Move-Item "$Driver.disabled" $Driver }
    $env:PATH = $PreviousPath
    $env:VK_DRIVER_FILES = $PreviousDriverFiles
    if ($Registered) {
        if ($null -eq $PreviousValue) { Remove-ItemProperty -Path $DriverKey -Name $Manifest }
        else { Set-ItemProperty -Path $DriverKey -Name $Manifest -Value $PreviousValue }
    }
    if ($CreatedKey) { Remove-Item $DriverKey }
}
# The deliberately failing negative control must not become the workflow step's exit code.
$global:LASTEXITCODE = 0
