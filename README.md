# valle-lavapipe

Prebuilt [Mesa](https://www.mesa3d.org/) lavapipe packages for Linux and Windows, on x86_64 and ARM64.

Lavapipe is Mesa's CPU Vulkan driver, built on llvmpipe and LLVM's JIT. It gives machines
without a GPU, such as CI runners and headless servers, a working Vulkan device. Valle uses it
for CPU rendering through wgpu.

## Packages

Packages use Mesa 26.2.6 (Vulkan API 1.4.354):

| Platform | LLVM | Vulkan loader |
|---|---|---|
| Linux x86_64 | 23.1.5 | 1.4.368 |
| Linux aarch64 | 23.1.5 | 1.4.368 |
| Windows x86_64 | 23.1.5 | 1.4.368 |
| Windows aarch64 | 23.1.5 | 1.4.368 |

**valle-lavapipe-{version}-linux-x86_64.tar.gz**

**valle-lavapipe-{version}-linux-aarch64.tar.gz**

Built from source in manylinux_2_28, requires only glibc 2.28+. LLVM, libdrm and the C++ runtime
are statically linked.

**valle-lavapipe-{version}-windows-x86_64.zip**

**valle-lavapipe-{version}-windows-aarch64.zip**

Built from source with MSVC on native x64 and ARM64 Windows runners. LLVM and the MSVC runtime
are statically linked; no separate Visual C++ runtime installation is required.
Targets Windows 10+ on x64 and Windows 11 on ARM64. Only Lavapipe and Vulkan Loader are packaged;
the D3D12 driver, OpenGL, video codecs, zlib and zstd are disabled.

The packages share this layout:
```
lib/
  libvulkan.so.1 / vulkan-1.dll           Vulkan loader
  libvulkan_lvp.so / vulkan_lvp.dll       lavapipe
  lvp_icd.x86_64.json / lvp_icd.aarch64.json  driver manifest
licenses/
THIRD_PARTY.md
```

## Use

`valle install` downloads, verifies and sets this up. By hand, after checking the SHA-256 and
extracting:

```bash
# Linux
export LD_LIBRARY_PATH=/path/to/valle-lavapipe/lib
export VK_DRIVER_FILES=/path/to/valle-lavapipe/lib/lvp_icd.x86_64.json
# On Linux ARM64, use lvp_icd.aarch64.json instead.
```

```powershell
# Windows
$env:PATH = "C:\path\to\valle-lavapipe\lib;$env:PATH"
$env:VK_DRIVER_FILES = "C:\path\to\valle-lavapipe\lib\lvp_icd.x86_64.json"
# On Windows ARM64, use lvp_icd.aarch64.json instead.
```

For wgpu, also set `WGPU_BACKEND=vulkan` and `WGPU_ADAPTER_NAME=llvmpipe`.

An elevated process on Windows, such as an administrator shell or a GitHub Actions runner,
ignores `VK_DRIVER_FILES`; the loader then reads drivers only from the registry. Register the
manifest there instead, from an administrator shell:

```powershell
reg add HKLM\SOFTWARE\Khronos\Vulkan\Drivers /v "C:\path\to\valle-lavapipe\lib\lvp_icd.x86_64.json" /t REG_DWORD /d 0 /f
```

## Development

CI downloads inputs from [sources.txt](sources.txt), verifies checksums, then builds and tests
all four release packages. Linux: built in manylinux_2_28 ([build-linux.sh](scripts/build-linux.sh))
on native `ubuntu-24.04` and `ubuntu-24.04-arm` runners. Each architecture runs the compute
probe on AlmaLinux 8, Ubuntu 22.04, Debian 12 and Ubuntu 24.04. Windows: LLVM, Lavapipe and Vulkan Loader
are built from source ([build-windows.ps1](scripts/build-windows.ps1)) on `windows-2025-vs2026`
and `windows-11-arm`. Both native architectures run the same compute probe against the
extracted archive ([run-windows.ps1](tests/run-windows.ps1)). The probe checks the DLL paths,
requires an llvmpipe CPU device, and verifies 256 compute results. A second run must fail with
the packaged driver removed. Any temporary registry registration is restored afterwards.

To build on a matching Windows host with Visual Studio C++ tools, Windows SDK and Python 3:

```powershell
./scripts/build-windows.ps1 -Architecture x64 -Version 26.2.6-local -Jobs 3
./tests/run-windows.ps1 -Package dist/valle-lavapipe-26.2.6-local-windows-x86_64.zip
# On native Windows ARM64, use -Architecture arm64 and windows-aarch64.zip.
```

The Windows script downloads and verifies its source inputs, installs pinned Python build
tools into a build-local virtual environment, and writes both the archive and its SHA-256.

CI caches only completed LLVM installations, separately for each OS and architecture.
Cache keys include the source pins, platform build script and build environment (the pinned
manylinux image or Windows runner image version). A changed key rebuilds LLVM; a matching
cache skips its compilation. Later build or test failures do not discard a completed LLVM
cache. Mesa, Vulkan Loader, packaging and runtime tests still run every time.

Publishing a release runs [release.yml](.github/workflows/release.yml) and uploads the packages.
Running the workflow manually with `publish` unset builds and tests without uploading.
Set `platform` to `windows` or `linux` to test only that platform's two architectures;
the default `all` tests all four packages. Publishing always builds and tests all four.

## License

Scripts: Apache-2.0 ([LICENSE](LICENSE)). Packages contain Mesa (MIT), LLVM (Apache-2.0 WITH
LLVM-exception), Vulkan loader (Apache-2.0), libdrm (MIT, Linux) and DirectX-Headers
(MIT, Windows); see [THIRD_PARTY.md](THIRD_PARTY.md).
