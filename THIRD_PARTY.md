# Third-party provenance and licenses

This repository holds only build scripts, tests and documentation, which are
Apache-2.0 as declared in [LICENSE](LICENSE). No upstream source or binary is
committed; CI downloads every input listed in [sources.txt](sources.txt) and
checks its SHA-256 before use. The released packages contain the following
upstream software, each under its own license. Each package carries those
licenses in `licenses/`.

Mesa and the listed library dependencies use permissive licenses. Compiler
runtimes have separate redistribution terms, described below. Mesa's source tree
also contains components that these Lavapipe-only builds do not enable, such as
GLX and hardware GPU drivers.

| Source | Pinned version | License | Form of use |
|---|---|---|---|
| [Mesa](https://www.mesa3d.org/) | 26.2.6 | MIT (some files BSL-1.0) | Built from source on Linux and Windows, lavapipe only. |
| [LLVM](https://llvm.org/) | 23.1.5 | Apache-2.0 WITH LLVM-exception | Built from source and statically linked into lavapipe, with only the matching CPU backend. |
| [Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader) | 1.4.368 | Apache-2.0 | Built from source on Linux and Windows. |
| [libdrm](https://gitlab.freedesktop.org/mesa/drm) | 2.4.134 | MIT | Linux: statically linked into lavapipe, which Mesa requires for any Vulkan driver. |
| [DirectX-Headers](https://github.com/microsoft/DirectX-Headers) | 1.619.1 | MIT | Windows: headers and static helpers used by Mesa's window-system support. The D3D12 Gallium driver is disabled. |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | 1.4.368 | Apache-2.0 | Build input only. |
| [glslang](https://github.com/KhronosGroup/glslang) | 16.6.0 | BSD-3-Clause and others | Build tool only, for Mesa's internal shaders and the test probe. |

The Linux libraries also contain the GCC C and C++ runtimes (`-static-libgcc`,
`-static-libstdc++`), which the GCC Runtime Library Exception permits in
programs under any license.

The Windows libraries contain the MSVC C and C++ runtimes (`/MT`), redistributed
under the Visual Studio toolchain's Microsoft license terms. Their exact version
follows the Visual Studio 2026 runner image and is recorded in the build output.

When updating an input, change its hash and URL in `sources.txt`, recheck its
license and update this table.
