# Build LLVM, Lavapipe and Vulkan Loader from the checksummed sources in sources.txt.
# Runs natively on an x64 or ARM64 Windows runner with Visual Studio C++ tools and Python 3.
# Example: pwsh -File scripts/build-windows.ps1 -Architecture arm64 -Version 26.2.6-local-msvc
param(
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Version,
    [ValidateRange(1, 64)][int]$Jobs = 2,
    [string]$VisualStudioPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows with MSVC installed.' }
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
$Build = Join-Path $Root "build/windows-msvc/$Architecture"
$Source = Join-Path $Root 'build/windows-msvc/sources'
$Dist = Join-Path $Root 'dist'
$HostArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$HostArchitecture = switch ($HostArchitecture) { 'ARM64' { 'arm64' } 'AMD64' { 'x64' } default { throw 'A 64-bit Windows host is required.' } }
if ($Architecture -ne $HostArchitecture) { throw "Use a native $Architecture runner for building and testing this package." }
$Cpu = if ($Architecture -eq 'arm64') { 'aarch64' } else { 'x86_64' }
$LlvmTarget = if ($Architecture -eq 'arm64') { 'AArch64' } else { 'X86' }
$Name = "valle-lavapipe-$Version-windows-$Cpu"
$Package = Join-Path $Build $Name
New-Item -ItemType Directory -Force -Path $Build, $Source, $Dist, "$Root/sources" | Out-Null

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

function Expand-Source([string]$File, [string]$Directory, [string[]]$Members = @()) {
    $Line = @(Get-Content "$Root/sources.txt" | Where-Object { $_ -match ('^[0-9a-f]{64}  ' + [regex]::Escape($File) + '  ') })
    if ($Line.Count -ne 1) { throw "Missing or duplicate source pin: $File" }
    $Hash, $Ignored, $Url = $Line[0] -split '\s+', 3
    $Archive = Join-Path $Root "sources/$File"
    if (!(Test-Path $Archive)) {
        Invoke-Checked curl.exe @('-fL', '--retry', '5', '--connect-timeout', '30', '-o', "$Archive.part", $Url)
        if ((Get-FileHash "$Archive.part" -Algorithm SHA256).Hash -ne $Hash) { throw "SHA-256 mismatch: $File.part" }
        Move-Item "$Archive.part" $Archive
    }
    if ((Get-FileHash $Archive -Algorithm SHA256).Hash -ne $Hash) { throw "SHA-256 mismatch: $File" }
    if (!(Test-Path "$Source/$Directory/.extracted")) {
        Invoke-Checked tar.exe (@('-xf', $Archive, '-C', $Source) + $Members)
        New-Item -ItemType File -Force "$Source/$Directory/.extracted" | Out-Null
    }
}

if (!$VisualStudioPath) {
    $Vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    if (!(Test-Path $Vswhere)) { throw 'Install Visual Studio C++ Build Tools and the Windows SDK first.' }
    $VisualStudioPath = & $Vswhere -latest -products '*' -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
    if ($LASTEXITCODE -ne 0 -or !$VisualStudioPath) { throw 'Visual Studio was not found.' }
}
$VsDevCmd = Join-Path $VisualStudioPath 'Common7/Tools/VsDevCmd.bat'
$Command = "`"$VsDevCmd`" -no_logo -host_arch=$HostArchitecture -arch=$Architecture && set"
$Lines = & $env:ComSpec /d /s /c "`"$Command`""
if ($LASTEXITCODE -ne 0) { throw "MSVC tools for $Architecture are unavailable." }
foreach ($Line in $Lines) {
    if ($Line -match '^([^=]+)=(.*)$') { Set-Item "Env:$($Matches[1])" $Matches[2] }
}
$env:CC = 'cl.exe'
$env:CXX = 'cl.exe'
Get-Command cl.exe, link.exe, lib.exe | Select-Object Name, Source | Format-Table
Write-Host "MSVC: $((Get-Item (Get-Command cl.exe).Source).VersionInfo.FileVersion)"

Write-Host '=== Preparing checksummed sources and build tools'
Expand-Source 'llvm-project-23.1.5.src.tar.xz' 'llvm-project-23.1.5.src' @(
    'llvm-project-23.1.5.src/llvm', 'llvm-project-23.1.5.src/cmake',
    'llvm-project-23.1.5.src/third-party', 'llvm-project-23.1.5.src/libc'
)
Expand-Source 'mesa-26.2.6.tar.xz' 'mesa-26.2.6'
Expand-Source 'glslang-16.6.0.tar.gz' 'glslang-16.6.0'
Expand-Source 'Vulkan-Headers-1.4.368.tar.gz' 'Vulkan-Headers-1.4.368'
Expand-Source 'Vulkan-Loader-1.4.368.tar.gz' 'Vulkan-Loader-1.4.368'
if (!(Test-Path "$Build/venv/Scripts/python.exe")) { Invoke-Checked python.exe @('-m', 'venv', "$Build/venv") }
$Python = "$Build/venv/Scripts/python.exe"
Invoke-Checked $Python @('-m', 'pip', 'install', 'meson==1.12.1', 'ninja==1.13.2', 'cmake==4.4.4', 'mako==1.4.3', 'pyyaml==6.0.3', 'packaging==26.3')
$env:PATH = "$Build/venv/Scripts;$Build/glslang/bin;$env:PATH"

$LlvmOptions = @(
    '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
    '-DBUILD_SHARED_LIBS=OFF', '-DLLVM_ENABLE_PROJECTS=', '-DLLVM_BUILD_TOOLS=OFF',
    '-DLLVM_BUILD_UTILS=OFF', '-DLLVM_INCLUDE_TESTS=OFF', '-DLLVM_INCLUDE_EXAMPLES=OFF',
    '-DLLVM_INCLUDE_BENCHMARKS=OFF', '-DLLVM_INCLUDE_DOCS=OFF', '-DLLVM_ENABLE_BINDINGS=OFF',
    '-DLLVM_ENABLE_ZLIB=OFF', '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_LIBXML2=OFF',
    '-DLLVM_ENABLE_LIBEDIT=OFF', '-DLLVM_ENABLE_LIBPFM=OFF', '-DLLVM_ENABLE_FFI=OFF',
    '-DLLVM_ENABLE_CURL=OFF', '-DLLVM_ENABLE_HTTPLIB=OFF', '-DLLVM_ENABLE_TERMINFO=OFF',
    '-DLLVM_BUILD_LLVM_DYLIB=OFF', '-DLLVM_LINK_LLVM_DYLIB=OFF', '-DLLVM_ENABLE_ASSERTIONS=OFF',
    '-DLLVM_ENABLE_RTTI=OFF', '-DLLVM_PARALLEL_LINK_JOBS=1'
)
Write-Host '=== Building host shader compiler'
Invoke-Checked cmake.exe @('-G', 'Ninja', '-S', "$Source/glslang-16.6.0", '-B', "$Build/glslang-build",
    '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded', "-DCMAKE_INSTALL_PREFIX=$Build/glslang",
    '-DENABLE_OPT=OFF', '-DENABLE_HLSL=OFF', '-DENABLE_PCH=OFF', '-DBUILD_EXTERNAL=OFF',
    '-DGLSLANG_TESTS=OFF', '-DENABLE_GLSLANG_BINARIES=ON')
Invoke-Checked cmake.exe @('--build', "$Build/glslang-build", '--parallel', "$Jobs", '--target', 'install')

$Prefix = "$Build/prefix"
Write-Host "=== Building LLVM 23.1.5 ($LlvmTarget, static MSVC runtime)"
Invoke-Checked cmake.exe (@('-G', 'Ninja', '-S', "$Source/llvm-project-23.1.5.src/llvm", '-B', "$Build/llvm-build",
    "-DCMAKE_INSTALL_PREFIX=$Prefix", "-DLLVM_HOST_TRIPLE=$Cpu-pc-windows-msvc", "-DLLVM_TARGETS_TO_BUILD=$LlvmTarget") + $LlvmOptions)
Invoke-Checked cmake.exe @('--build', "$Build/llvm-build", '--parallel', "$Jobs", '--target', 'install', 'llvm-config')
New-Item -ItemType Directory -Force "$Prefix/bin" | Out-Null
Copy-Item "$Build/llvm-build/bin/llvm-config.exe" "$Prefix/bin/llvm-config.exe"
$LlvmConfig = "$Prefix/bin/llvm-config.exe".Replace('\', '/')
$NativeFile = "$Build/native.ini"
"[binaries]`nllvm-config = '$LlvmConfig'" | Set-Content $NativeFile -Encoding utf8
$LlvmVersion = & $LlvmConfig --version
if ($LASTEXITCODE -ne 0 -or $LlvmVersion.Trim() -ne '23.1.5') { throw 'Unexpected LLVM version.' }

Write-Host '=== Building Mesa 26.2.6 (Lavapipe only)'
$MesonReconfigure = if (Test-Path "$Build/mesa-build/meson-private/coredata.dat") { @('--reconfigure') } else { @() }
Invoke-Checked meson.exe (@('setup', "$Build/mesa-build", "$Source/mesa-26.2.6",
    '--native-file', $NativeFile, "--prefix=$Build/mesa-install", "--cmake-prefix-path=$Prefix", '--buildtype=release', '--default-library=static',
    '-Db_ndebug=true', '-Db_vscrt=mt', '-Dvulkan-drivers=swrast', '-Dgallium-drivers=', '-Dplatforms=',
    '-Dopengl=false', '-Dgles1=disabled', '-Dgles2=disabled', '-Dglvnd=disabled',
    '-Dglx=disabled', '-Degl=disabled', '-Dgbm=disabled', '-Dllvm=enabled', '-Dshared-llvm=disabled',
    '-Dcpp_rtti=false', '-Dshader-cache=disabled', '-Dzlib=disabled', '-Dzstd=disabled',
    '-Dxmlconfig=disabled', '-Dexpat=disabled', '-Dlibunwind=disabled', '-Dvalgrind=disabled',
    '-Dlmsensors=disabled', '-Dandroid-libbacktrace=disabled', '-Dmicrosoft-clc=disabled',
    '-Dgallium-va=disabled', '-Dvideo-codecs=', '-Dspirv-tools=disabled', '-Dmin-windows-version=10',
    '-Dvulkan-manifest-per-architecture=false', '-Dvulkan-layers=', '-Dtools=', '-Dbuild-tests=false') + $MesonReconfigure)
Invoke-Checked ninja.exe @('-C', "$Build/mesa-build", "-j$Jobs", 'install')

Write-Host '=== Building Vulkan Loader 1.4.368'
Invoke-Checked cmake.exe @('-G', 'Ninja', '-S', "$Source/Vulkan-Headers-1.4.368", '-B', "$Build/headers-build", "-DCMAKE_INSTALL_PREFIX=$Prefix")
Invoke-Checked cmake.exe @('--build', "$Build/headers-build", '--target', 'install')
Invoke-Checked cmake.exe @('-G', 'Ninja', '-S', "$Source/Vulkan-Loader-1.4.368", '-B', "$Build/loader-build",
    '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_PREFIX_PATH=$Prefix", "-DCMAKE_INSTALL_PREFIX=$Build/loader-install",
    '-DDYNAMIC_LINK_MSVC_RUNTIME_LIBRARY=OFF', '-DBUILD_TESTS=OFF')
Invoke-Checked cmake.exe @('--build', "$Build/loader-build", '--parallel', "$Jobs", '--target', 'install')

Write-Host '=== Packaging and checking PE imports'
New-Item -ItemType Directory -Force "$Package/lib", "$Package/licenses" | Out-Null
Copy-Item "$Build/mesa-install/bin/vulkan_lvp.dll", "$Build/loader-install/bin/vulkan-1.dll" "$Package/lib/"
$Manifest = Get-ChildItem "$Build/mesa-install" -Recurse -Filter 'lvp_icd.json'
if (@($Manifest).Count -ne 1) { throw "Expected one $Cpu ICD manifest." }
$Icd = Get-Content $Manifest.FullName -Raw | ConvertFrom-Json
$Icd.ICD.library_path = '.\vulkan_lvp.dll'
$Icd | ConvertTo-Json -Depth 8 | Set-Content "$Package/lib/lvp_icd.$Cpu.json" -Encoding ascii
Copy-Item "$Source/mesa-26.2.6/docs/license.rst" "$Package/licenses/mesa.rst"
Copy-Item "$Source/mesa-26.2.6/licenses/MIT" "$Package/licenses/mesa-MIT.txt"
Copy-Item "$Source/mesa-26.2.6/licenses/BSL-1.0" "$Package/licenses/mesa-BSL-1.0.txt"
Copy-Item "$Source/llvm-project-23.1.5.src/llvm/LICENSE.TXT" "$Package/licenses/llvm.txt"
Copy-Item "$Source/Vulkan-Loader-1.4.368/LICENSE.txt" "$Package/licenses/vulkan-loader.txt"
Copy-Item "$Root/THIRD_PARTY.md" "$Package/"
foreach ($Dll in Get-ChildItem "$Package/lib/*.dll") {
    $Headers = & dumpbin.exe /headers $Dll.FullName
    if ($LASTEXITCODE -ne 0 -or !($Headers -match "machine \($Architecture\)")) { throw "Wrong PE architecture: $($Dll.Name)" }
    $Imports = & dumpbin.exe /dependents $Dll.FullName
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $($Dll.Name)" }
    $Imports | Set-Content "$Build/$($Dll.Name).imports.txt"
    # /MT must keep compiler runtimes and optional third-party DLLs out of the package's imports.
    $Allowed = '^(KERNEL32|NTDLL|ADVAPI32|USER32|GDI32|SHELL32|OLE32|OLEAUT32|WS2_32|VERSION|SHLWAPI|BCRYPT|CFGMR32|DEVOBJ|SETUPAPI|PSAPI|DBGHELP|RPCRT4|ucrtbase|api-ms-win-.+|ext-ms-win-.+)\.dll$'
    foreach ($Line in $Imports) {
        $Dependency = $Line.Trim()
        if ($Dependency -match '^[\w.-]+\.dll$' -and $Dependency -notmatch $Allowed) { throw "Unexpected dependency in $($Dll.Name): $Dependency" }
    }
}
$Exports = & dumpbin.exe /exports "$Package/lib/vulkan_lvp.dll"
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Lavapipe exports.' }
foreach ($Entry in @('vk_icdGetInstanceProcAddr', 'vk_icdGetPhysicalDeviceProcAddr', 'vk_icdNegotiateLoaderICDInterfaceVersion')) {
    if (!($Exports -match "\b$Entry\b")) { throw "Missing ICD export: $Entry" }
}
Invoke-Checked cl.exe @('/nologo', '/O2', '/MT', '/std:c11', '/D_CRT_SECURE_NO_WARNINGS', "/I$Prefix/include", "/I$Root/tests",
    "$Root/tests/probe.c", "/Fo$Build/probe.obj", "/Fe$Dist/probe-windows-$Cpu.exe")
Compress-Archive -LiteralPath $Package -DestinationPath "$Dist/$Name.zip" -CompressionLevel Optimal -Force
$PackageHash = (Get-FileHash "$Dist/$Name.zip" -Algorithm SHA256).Hash.ToLowerInvariant()
"$PackageHash  $Name.zip" | Set-Content "$Dist/$Name.zip.sha256" -Encoding ascii
Write-Host "Built $Dist/$Name.zip"
Write-Host "Run tests/run-windows.ps1 -Package `"$Dist/$Name.zip`" to validate the archive on Windows."
