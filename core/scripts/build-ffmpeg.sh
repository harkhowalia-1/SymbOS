#!/bin/bash
# Cross-compile the FFmpeg revision bundled with EKA2L1 (libavcodec 59) for one
# Apple platform. Output: core/out/ffmpeg/<platform>/{include,lib}
#
#   core/scripts/build-ffmpeg.sh ios     # iPhone/iPad, arm64
#   core/scripts/build-ffmpeg.sh macos   # Mac, arm64
#
# Uses the same decoder/demuxer set as EKA2L1's own macOS script, so the API the
# emulator was written against matches exactly. Assembly is disabled: video in
# Symbian apps is low resolution and portability matters more than speed here.
set -euo pipefail

PLATFORM="${1:?usage: build-ffmpeg.sh ios|macos}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/external/eka2l1/src/external/ffmpeg"
OUT="${ROOT}/core/out/ffmpeg/${PLATFORM}"
WORK="${ROOT}/core/build/ffmpeg-src-${PLATFORM}"

if [ -f "${OUT}/lib/libavcodec.a" ]; then
    echo "FFmpeg for ${PLATFORM} already built at ${OUT}"
    exit 0
fi

case "${PLATFORM}" in
    ios)
        SDK=iphoneos
        MINVER="-miphoneos-version-min=16.0"
        ;;
    macos)
        SDK=macosx
        MINVER="-mmacosx-version-min=13.0"
        ;;
    *) echo "unknown platform ${PLATFORM}"; exit 1 ;;
esac

CC="$(xcrun -sdk ${SDK} -f clang)"
SYSROOT="$(xcrun -sdk ${SDK} --show-sdk-path)"
CFLAGS="-arch arm64 ${MINVER} -isysroot ${SYSROOT} -O2 -D__STDC_CONSTANT_MACROS"

echo "Copying FFmpeg sources to ${WORK}"
rm -rf "${WORK}"
mkdir -p "${WORK}"
# Copy (not build in place) so the submodule stays clean.
rsync -a --exclude '.git' --exclude 'macos' --exclude 'windows' --exclude 'Windows' \
    --exclude 'linux' --exclude 'android' "${SRC}/" "${WORK}/"
cd "${WORK}"

./configure \
    --prefix="${OUT}" \
    --enable-cross-compile \
    --target-os=darwin \
    --arch=aarch64 \
    --cc="${CC}" \
    --sysroot="${SYSROOT}" \
    --extra-cflags="${CFLAGS}" \
    --extra-ldflags="-arch arm64 ${MINVER} -isysroot ${SYSROOT}" \
    --disable-shared --enable-static --enable-pic \
    --disable-asm --disable-x86asm \
    --disable-everything \
    --disable-avdevice --disable-avfilter --disable-postproc --disable-network \
    --disable-programs --disable-doc \
    --disable-videotoolbox --disable-audiotoolbox --disable-securetransport \
    --enable-zlib \
    --enable-decoder=h264,mpeg4,h263,h263p,mpeg2video,mjpeg,mjpegb \
    --enable-decoder=aac,aac_latm,wavpack,amrnb,amrwb,mp3,pcm_s16le,pcm_s8 \
    --enable-demuxer=h264,m4v,mp3,mpegvideo,mpegps,mjpeg,mov,avi,aac,amr,amrnb,amrwb,pcm_s16le,pcm_s8,wav \
    --enable-encoder=pcm_s16le \
    --enable-muxer=amr,avi,mp3,wav,pcm_s16le,pcm_s8,ogg \
    --enable-parser=h264,mpeg4video,mpegvideo,aac,aac_latm,mpegaudio \
    --enable-protocol=file

make -j"$(sysctl -n hw.logicalcpu)"
make install
echo "FFmpeg for ${PLATFORM} installed to ${OUT}"
