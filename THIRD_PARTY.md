# Third-party provenance and licenses

This repository holds only build scripts, tests and documentation, which are
Apache-2.0 as declared in [LICENSE](LICENSE). No upstream source or binary is
committed; CI downloads every input listed in [sources.txt](sources.txt) and
checks its SHA-256 before use. The released packages contain the following
upstream software, each under its own license. Each package carries those
licenses in `licenses/`.

Only permissive licenses apply to what the packages contain. Mesa's source tree
also includes GPL- and SGI-licensed files (GLX, the SVGA driver, Linux uAPI
headers); none of them is part of lavapipe, which the build enables alone.

| Source | Pinned version | License | Form of use |
|---|---|---|---|
| [Mesa](https://www.mesa3d.org/) | 25.2.7 | MIT (some files BSL-1.0) | Linux: built from source, lavapipe only. Windows: `vulkan_lvp.dll` from mesa-dist-win. |
| [LLVM](https://llvm.org/) | 21.1.6 | Apache-2.0 WITH LLVM-exception | Statically linked into lavapipe on both platforms. |
| [Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader) | 1.4.328 | Apache-2.0 | Linux: built from source. Windows: `vulkan-1.dll` from LunarG's Vulkan Runtime 1.4.328.1. |
| [libdrm](https://gitlab.freedesktop.org/mesa/drm) | 2.4.134 | MIT | Linux: statically linked into lavapipe, which Mesa requires for any Vulkan driver. |
| [mesa-dist-win](https://github.com/pal1000/mesa-dist-win) | 25.2.7 | MIT | Windows: the prebuilt Mesa release that `vulkan_lvp.dll` is taken from. |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | 1.4.328 | Apache-2.0 | Build input only. |
| [glslang](https://github.com/KhronosGroup/glslang) | 16.6.0 | BSD-3-Clause and others | Build tool only, for Mesa's internal shaders and the test probe. |

The Linux libraries also contain the GCC C and C++ runtimes (`-static-libgcc`,
`-static-libstdc++`), which the GCC Runtime Library Exception permits in
programs under any license.

When updating an input, change its hash and URL in `sources.txt`, recheck its
license and update this table.
