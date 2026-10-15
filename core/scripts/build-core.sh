#!/bin/bash
# Build the EKA2L1 emulator core as one static library the Xcode project links.
#
#   core/scripts/build-core.sh ios     -> core/out/ios/libHalcyonCore.a
#   core/scripts/build-core.sh macos   -> core/out/macos/libHalcyonCore.a
#
# Each output folder also gets:
#   include/ios/emu_bridge.h   the C++ API the app's Objective-C++ wrapper calls
#   assets/                    shaders, MIDI banks, compat db and Symbian patch DLLs
#                              (copied into the app bundle; staged to the data dir on launch)
#   SDL2.framework             macOS only, embedded in the Mac app
#
# Requirements: Xcode, ninja (brew install ninja). CMake 3.31 is fetched once,
# because CMake 4.x cannot configure several of EKA2L1's older submodules.
set -euo pipefail

PLATFORM="${1:?usage: build-core.sh ios|macos}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="${ROOT}/external/eka2l1"
BUILD="${ROOT}/core/build/${PLATFORM}"
OUT="${ROOT}/core/out/${PLATFORM}"
JOBS="$(sysctl -n hw.logicalcpu)"

# ---- Toolchain ---------------------------------------------------------------
CACHE="${HOME}/Library/Caches/halcyon-build"
CMAKE="${CACHE}/cmake-3.31.6-macos-universal/CMake.app/Contents/bin/cmake"
if [ ! -x "${CMAKE}" ]; then
    echo "Fetching CMake 3.31.6 (one-time)..."
    mkdir -p "${CACHE}"
    curl -fsSL -o "${CACHE}/cmake.tar.gz" \
        https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-macos-universal.tar.gz
    tar xzf "${CACHE}/cmake.tar.gz" -C "${CACHE}"
fi
command -v ninja >/dev/null || { echo "ninja not found: brew install ninja"; exit 1; }

# ---- Sources -----------------------------------------------------------------
if [ ! -f "${CORE}/CMakeLists.txt" ]; then
    echo "EKA2L1 submodule missing: git submodule update --init external/eka2l1"
    exit 1
fi
echo "Fetching EKA2L1's own submodules (shallow)..."
git -C "${CORE}" submodule update --init --recursive --depth 1 --jobs 8

python3 "${ROOT}/core/scripts/patch-core.py" "${CORE}"
"${ROOT}/core/scripts/build-ffmpeg.sh" "${PLATFORM}"

# ---- Configure ---------------------------------------------------------------
COMMON_ARGS=(
    -S "${CORE}" -B "${BUILD}" -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DEKA2L1_BUILD_TOOLS=OFF
    -DEKA2L1_BUILD_TESTS=OFF
    -DEKA2L1_ENABLE_SCRIPTING_ABILITY=OFF
    -DEKA2L1_BUILD_VULKAN_BACKEND=OFF
    -DEKA2L1_ENABLE_DISCORD_RICH_PRESENCE=OFF
    -DHALCYON_FFMPEG_DIR="${ROOT}/core/out/ffmpeg/${PLATFORM}"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    # The iOS port defines FMT_USE_CONSTEVAL=0 for Xcode 26 and fmt 10 defines it again;
    # harmless, but Dynarmic's strict flags and precompiled headers made it fatal.
    -DDYNARMIC_WARNINGS_AS_ERRORS=OFF
    -DDYNARMIC_FATAL_ERRORS=OFF
    -DDYNARMIC_USE_PRECOMPILED_HEADERS=OFF
    -DCMAKE_C_FLAGS="-Wno-macro-redefined"
    # Xcode 26's libc++ dropped std::unary_function, which the bundled Boost (used by
    # Dynarmic) still needs. The iOS port sets this for iOS only; the Mac needs it too.
    -DCMAKE_CXX_FLAGS="-Wno-macro-redefined -D_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION -D_HAS_AUTO_PTR_ETC=0"
)

case "${PLATFORM}" in
    ios)
        TARGET=eka2l1_ios_bridge
        "${CMAKE}" "${COMMON_ARGS[@]}" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphoneos \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
            -DUSE_AUDIOUNIT=0
        # ^ cubeb's AudioUnit backend uses Mac-only CoreAudio APIs; on iOS the port
        #   plays audio through its own RemoteIO backend instead.
        ;;
    macos)
        TARGET=halcyon_mac_bridge
        "${CMAKE}" "${COMMON_ARGS[@]}" \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DHALCYON_EMBED_DIR="${ROOT}/core/embed"
        ;;
    *) echo "unknown platform ${PLATFORM}"; exit 1 ;;
esac

# ---- Build -------------------------------------------------------------------
# -k 0: keep going after a failure so one CI run reports every error, not just the first.
"${CMAKE}" --build "${BUILD}" --target "${TARGET}" -j"${JOBS}" -- -k 0

# ---- Package -----------------------------------------------------------------
rm -rf "${OUT}"
mkdir -p "${OUT}/include/ios" "${OUT}/assets/resources" "${OUT}/assets/compat" "${OUT}/assets/patch"

# Merge every static library the target pulled in, plus FFmpeg, into one archive.
# Only libraries that were actually built as dependencies of TARGET exist in the tree.
ARCHIVES=()
while IFS= read -r lib; do ARCHIVES+=("$lib"); done < <(
    find "${BUILD}" -name '*.a' -not -path '*/CMakeFiles/*' -not -name 'libCatch2*' | sort)
for lib in avformat avcodec swscale avutil swresample; do
    ARCHIVES+=("${ROOT}/core/out/ffmpeg/${PLATFORM}/lib/lib${lib}.a")
done
echo "Merging ${#ARCHIVES[@]} archives into libHalcyonCore.a"
libtool -static -no_warning_for_no_symbols -o "${OUT}/libHalcyonCore.a" "${ARCHIVES[@]}"

cp "${CORE}/src/emu/ios/include/ios/emu_bridge.h" "${OUT}/include/ios/"
cp "${ROOT}/core/embed/halcyon_host.h" "${OUT}/include/"

# Point the Xcode project at the real core (it builds against a mock otherwise).
"${ROOT}/core/scripts/write-xcconfig.sh" "${PLATFORM}"

RES="${CORE}/src/emu/drivers/resources"
if [ "${PLATFORM}" = "ios" ]; then
    cp -R "${RES}/gles/." "${OUT}/assets/resources/"      # OpenGL ES shaders
else
    cp -R "${RES}/gl/." "${OUT}/assets/resources/"        # desktop OpenGL shaders
    cp -R "${CORE}/src/external/sdl2/macos/SDL2.framework" "${OUT}/"
fi
mkdir -p "${OUT}/assets/resources/upscale"
cp -R "${RES}/upscale/." "${OUT}/assets/resources/upscale/" 2>/dev/null || true
cp "${RES}/defaultbank.hsb" "${RES}/defaultbank.sf2" "${OUT}/assets/resources/"
cp -R "${CORE}/miscs/compat/." "${OUT}/assets/compat/"
cp -R "${BUILD}/bin/patch/." "${OUT}/assets/patch/" 2>/dev/null || echo "warning: no patch DLLs were staged"

echo "Core for ${PLATFORM}: ${OUT}"
ls -la "${OUT}"
