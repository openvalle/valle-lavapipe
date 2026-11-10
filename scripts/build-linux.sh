#!/bin/bash
# Builds lavapipe and the Vulkan loader as one folder that needs only glibc 2.28. Runs inside
# quay.io/pypa/manylinux_2_28_{x86_64,aarch64} with the repository at /work and the inputs
# already in /work/sources (scripts/fetch.sh); builds for the container's native architecture.
set -euo pipefail

: "${VERSION:?set VERSION, such as 0.1.0}"
BUILD_ARCH=$(uname -m)
case "$BUILD_ARCH" in
  x86_64) LLVM_TARGET=X86; ELF_LOADER=ld-linux-x86-64 ;;
  aarch64) LLVM_TARGET=AArch64; ELF_LOADER=ld-linux-aarch64 ;;
  *) echo "unsupported Linux architecture: $BUILD_ARCH"; exit 1 ;;
esac
JOBS=${JOBS:-$(nproc)}
SRC=/work/sources
B=/build
PREFIX=$B/prefix
NAME=valle-lavapipe-$VERSION-linux-$BUILD_ARCH
mkdir -p "$B" "$PREFIX" /work/dist
cd "$B"

echo "=== Installing build tools"
dnf install -y bison flex
/opt/python/cp312-cp312/bin/python -m venv "$B/venv"
"$B/venv/bin/pip" install --quiet meson==1.12.1 ninja==1.13.2 cmake==4.4.4 mako==1.4.3 pyyaml==6.0.3 packaging==26.3
export PATH="$B/venv/bin:$PATH"

echo "=== Building LLVM 23.1.5 (static, $LLVM_TARGET only)"
mkdir -p llvm-src
# LLVM 23 also needs libc's common utilities while configuring LLVM itself.
tar xJf "$SRC/llvm-project-23.1.5.src.tar.xz" -C llvm-src --strip-components=1 \
  llvm-project-23.1.5.src/llvm llvm-project-23.1.5.src/cmake \
  llvm-project-23.1.5.src/third-party llvm-project-23.1.5.src/libc
cmake -G Ninja -S llvm-src/llvm -B llvm-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DLLVM_TARGETS_TO_BUILD="$LLVM_TARGET" -DLLVM_ENABLE_PROJECTS= \
  -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TOOLS=ON -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_HTTPLIB=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF -DLLVM_LINK_LLVM_DYLIB=OFF -DLLVM_ENABLE_PIC=ON \
  -DLLVM_ENABLE_ASSERTIONS=OFF
ninja -C llvm-build -j"$JOBS" install llvm-config
# Without LLVM's tools, its install makes no bin/.
mkdir -p "$PREFIX/bin"
cp llvm-build/bin/llvm-config "$PREFIX/bin/"

echo "=== Building glslang 16.6.0 (build tool)"
# glslangValidator, which Mesa's Vulkan runtime compiles its GLSL with; a build tool only. Its
# release binaries need glibc 2.34, newer than this image.
tar xzf "$SRC/glslang-16.6.0.tar.gz"
cmake -G Ninja -S glslang-16.6.0 -B glslang-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$B/glslang" \
  -DENABLE_OPT=OFF -DENABLE_HLSL=OFF -DENABLE_PCH=OFF -DBUILD_EXTERNAL=OFF \
  -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=ON
ninja -C glslang-build -j"$JOBS" install
export PATH="$B/glslang/bin:$PATH"

echo "=== Building libdrm 2.4.134 (static)"
# libdrm, static: Mesa's Vulkan runtime on Linux requires it even without a window system
# (meson.build: with_dri2 follows any Vulkan driver), so it is linked in rather than needed.
tar xJf "$SRC/libdrm-2.4.134.tar.xz"
meson setup libdrm-build libdrm-2.4.134 --prefix="$PREFIX" --libdir=lib \
  --buildtype=release --default-library=static -Db_staticpic=true \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
  -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled \
  -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled -Dcairo-tests=disabled \
  -Dman-pages=disabled -Dvalgrind=disabled -Dudev=false -Dtests=false
ninja -C libdrm-build -j"$JOBS" install
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

echo "=== Building Mesa 26.2.6 (lavapipe only)"
# Mesa: lavapipe only, with LLVM, libdrm and the C++ runtime linked in. The image's libdrm-devel
# goes first, so only the static one above is found. The version script exports only the
# loader's entry points: exported symbols are roots that --gc-sections keeps, so exporting
# LLVM's would keep all of LLVM.
rpm -e --nodeps libdrm-devel 2>/dev/null || true
tar xJf "$SRC/mesa-26.2.6.tar.xz"
printf '{\n  global: vk_icd*;\n  local: *;\n};\n' > "$B/lvp.map"
printf '[binaries]\nllvm-config = %s\n' "'$PREFIX/bin/llvm-config'" > native.ini
meson setup mesa-build mesa-26.2.6 --native-file native.ini \
  --prefix=/usr --libdir=lib --buildtype=release -Db_ndebug=true \
  -Dvulkan-drivers=swrast -Dgallium-drivers= -Dplatforms= \
  -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dglvnd=disabled \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dllvm=enabled -Dshared-llvm=disabled -Dcpp_rtti=false -Dshader-cache=disabled \
  -Dzlib=disabled -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled \
  -Dlibunwind=disabled -Dvalgrind=disabled -Dlmsensors=disabled \
  -Dandroid-libbacktrace=disabled -Dmicrosoft-clc=disabled \
  -Dgallium-va=disabled -Dvideo-codecs= \
  -Dvulkan-layers= -Dtools= -Dbuild-tests=false \
  -Dcpp_link_args="-static-libstdc++ -static-libgcc -Wl,--version-script=$B/lvp.map" \
  -Dc_link_args="-static-libgcc -Wl,--version-script=$B/lvp.map"
ninja -C mesa-build -j"$JOBS"
DESTDIR="$B/mesa-install" ninja -C mesa-build install

echo "=== Building Vulkan loader 1.4.368"
# The Vulkan loader, without any window system.
tar xzf "$SRC/Vulkan-Headers-1.4.368.tar.gz"
tar xzf "$SRC/Vulkan-Loader-1.4.368.tar.gz"
cmake -G Ninja -S Vulkan-Headers-1.4.368 -B headers-build -DCMAKE_INSTALL_PREFIX="$PREFIX"
ninja -C headers-build install
cmake -G Ninja -S Vulkan-Loader-1.4.368 -B loader-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF \
  -DBUILD_WSI_WAYLAND_SUPPORT=OFF -DBUILD_WSI_DIRECTFB_SUPPORT=OFF -DBUILD_TESTS=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS='-static-libgcc'
ninja -C loader-build -j"$JOBS"
DESTDIR="$B/loader-install" ninja -C loader-build install

echo "=== Packaging"
# The package: lib/ holds both libraries and a manifest naming the driver beside it, as the
# Windows package's does, so the folder works wherever it is extracted.
P="$B/$NAME"
mkdir -p "$P/lib" "$P/licenses"
cp "$(find "$B/mesa-install" -name libvulkan_lvp.so -print -quit)" "$P/lib/libvulkan_lvp.so"
cp "$(find "$B/loader-install" -name 'libvulkan.so.1.*' -type f -print -quit)" "$P/lib/libvulkan.so.1"
strip --strip-unneeded "$P/lib/"*.so*
python3 - "$(find "$B/mesa-install" -name "lvp_icd.$BUILD_ARCH.json" -print -quit)" "$P/lib/lvp_icd.$BUILD_ARCH.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["ICD"]["library_path"] = "./libvulkan_lvp.so"
json.dump(m, open(sys.argv[2], "w"), indent=4)
EOF
cp mesa-26.2.6/docs/license.rst "$P/licenses/mesa.rst"
cp mesa-26.2.6/licenses/MIT "$P/licenses/mesa-MIT.txt"
cp mesa-26.2.6/licenses/BSL-1.0 "$P/licenses/mesa-BSL-1.0.txt"
cp llvm-src/llvm/LICENSE.TXT "$P/licenses/llvm.txt"
cp Vulkan-Loader-1.4.368/LICENSE.txt "$P/licenses/vulkan-loader.txt"
# libdrm ships no license file; its MIT terms are in each source's header.
sed -n '8,/^ \*\/$/p' libdrm-2.4.134/xf86drm.h > "$P/licenses/libdrm.txt"
cp /work/THIRD_PARTY.md "$P/"

echo "=== Validating"
# Nothing but glibc, and the loader's three entry points.
if readelf -d "$P/lib/"*.so* | grep NEEDED | grep -v -E "\[(libc|libm|libdl|libpthread|librt|$ELF_LOADER)\.so\.[0-9]+\]"; then
  echo "a dependency outside glibc"; exit 1
fi
glibc=$(objdump -T "$P/lib/"*.so* | grep -o -E 'GLIBC_[0-9.]+' | sort -t. -k1,1 -k2,2n -k3,3n -u | tail -1)
[ "$glibc" = GLIBC_2.28 ] || { echo "needs $glibc, not GLIBC_2.28"; exit 1; }
for e in vk_icdGetInstanceProcAddr vk_icdGetPhysicalDeviceProcAddr vk_icdNegotiateLoaderICDInterfaceVersion; do
  nm -D --defined-only "$P/lib/libvulkan_lvp.so" | grep -q " $e\$" || { echo "$e not exported"; exit 1; }
done

echo "=== Creating archive"
tar -C "$B" -czf "/work/dist/$NAME.tar.gz" "$NAME"
echo "Built /work/dist/$NAME.tar.gz"

echo "=== Building the probe"
# Built here too, so it needs nothing newer than the package does; it is not in the package.
gcc -O2 -Wall -I"$PREFIX/include" -I/work/tests -o "/work/dist/probe-$BUILD_ARCH" /work/tests/probe.c -ldl -lm
