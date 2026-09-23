#!/bin/bash
# Mesa >= 24 refuses to configure RADV -- or any other Vulkan driver that
# builds BVH/ray-tracing shaders -- unless glslang >= 12.2 is available on the
# build machine ("meson.build: ERROR: glslang >= 12.2 is required").  Ubuntu
# 22.04 only ships 11.8.  Valve's arm64 image never trips over this because it
# builds mesa without any Vulkan driver; the x86_64 target builds RADV.
#
# mesa3d_cross.mk runs meson with PATH=/usr/bin:/usr/local/bin:..., so the new
# binary has to replace the distro one in /usr/bin rather than shadow it from
# /usr/local.
set -euo pipefail

GLSLANG_VERSION=15.1.0

# glslang 15 needs CMake >= 3.27; Ubuntu 22.04 ships 3.22.  The builder already
# gets meson from pip, so take CMake from there too (manylinux wheel).
python3 -m pip install --quiet "cmake>=3.27"
CMAKE="$(python3 -c 'import cmake, os; print(os.path.join(cmake.CMAKE_BIN_DIR, "cmake"))')"
"${CMAKE}" --version | head -1

apt-get -qq update
apt-get remove -y glslang-tools || true

cd /tmp
# curl rather than git: GitHub's edge protection answers 401 to Ubuntu 22.04's
# git when it negotiates HTTP/2, while curl gets through.
curl -fsSL -o glslang.tar.gz \
    "https://github.com/KhronosGroup/glslang/archive/refs/tags/${GLSLANG_VERSION}.tar.gz"
tar -xzf glslang.tar.gz
"${CMAKE}" -S "glslang-${GLSLANG_VERSION}" -B glslang-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DENABLE_OPT=OFF \
    -DGLSLANG_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF
"${CMAKE}" --build glslang-build -j"$(nproc)"
"${CMAKE}" --install glslang-build
rm -rf glslang.tar.gz "glslang-${GLSLANG_VERSION}" glslang-build /var/lib/apt/lists/*

glslangValidator --version | head -1
