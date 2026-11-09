# valle-lavapipe

Prebuilt [Mesa](https://www.mesa3d.org/) lavapipe packages for Linux and Windows, x86_64.

Lavapipe is Mesa's CPU Vulkan driver, built on llvmpipe and LLVM's JIT. It gives machines
without a GPU, such as CI runners and headless servers, a working Vulkan device. Valle uses it
for CPU rendering through wgpu.

## Packages

Each [release](https://github.com/openvalle/valle-lavapipe/releases) contains two packages with
checksums (Mesa 25.2.7, LLVM 21.1.6, Vulkan loader 1.4.328, Vulkan API 1.4.318):

**valle-lavapipe-{version}-linux-x86_64.tar.gz**  
Built from source in manylinux_2_28, requires only glibc 2.28+. LLVM, libdrm and the C++ runtime
are statically linked.

**valle-lavapipe-{version}-windows-x86_64.tar.gz**  
Lavapipe from [mesa-dist-win](https://github.com/pal1000/mesa-dist-win), Vulkan loader from
LunarG's runtime, repackaged.

Both have the same layout:
```
lib/
  libvulkan.so.1 / vulkan-1.dll           Vulkan loader
  libvulkan_lvp.so / vulkan_lvp.dll       lavapipe
  lvp_icd.x86_64.json                     driver manifest
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
```

```powershell
# Windows
$env:PATH = "C:\path\to\valle-lavapipe\lib;$env:PATH"
$env:VK_DRIVER_FILES = "C:\path\to\valle-lavapipe\lib\lvp_icd.x86_64.json"
```

For wgpu, also set `WGPU_BACKEND=vulkan` and `WGPU_ADAPTER_NAME=llvmpipe`.

## Development

CI downloads inputs from [sources.txt](sources.txt), verifies checksums, then builds and tests
both packages. Linux: built in manylinux_2_28 ([build-linux.sh](scripts/build-linux.sh)), tested
with a compute probe on bare distributions. Windows: repackaged
([package-windows.sh](scripts/package-windows.sh)), tested by compiling and running the same
probe.

Publishing a release runs [release.yml](.github/workflows/release.yml) and uploads the packages.
Running the workflow manually with `publish` unset builds and tests without uploading.

## License

Scripts: Apache-2.0 ([LICENSE](LICENSE)). Packages contain Mesa (MIT), LLVM (Apache-2.0 WITH
LLVM-exception), Vulkan loader (Apache-2.0) and libdrm (MIT); see
[THIRD_PARTY.md](THIRD_PARTY.md).
