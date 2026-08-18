#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
manifest="$repo_root/Dependencies/ffmpeg/versions.env"
build_root="$repo_root/build/vendor"
download_dir="$build_root/downloads"
source_dir="$build_root/sources"
prefix_dir="$build_root/prefix"
tool_dir="$build_root/ffmpeg"
source_offer="$tool_dir/source-offer"

if [[ "$build_root" != "$repo_root/build/vendor" || "$repo_root" == "/" ]]; then
  print -u2 "Refusing unsafe build root: $build_root"
  exit 1
fi

source "$manifest"
mkdir -p "$download_dir"
rm -rf -- "$source_dir" "$prefix_dir" "$tool_dir" "$build_root/libaom-build"
mkdir -p "$download_dir" "$source_dir" "$prefix_dir" "$tool_dir/bin" "$source_offer"

download_and_verify() {
  local url="$1"
  local expected_sha="$2"
  local archive="$3"
  if [[ -f "$archive" ]] && print "$expected_sha  $archive" | shasum -a 256 -c -; then
    return
  fi
  local partial="$archive.partial"
  rm -f -- "$archive" "$partial"
  curl --fail --location --retry 3 --output "$partial" "$url"
  print "$expected_sha  $partial" | shasum -a 256 -c -
  mv "$partial" "$archive"
}

ffmpeg_archive="$download_dir/ffmpeg-$FFMPEG_VERSION.tar.xz"
libvpx_archive="$download_dir/libvpx-$LIBVPX_VERSION.tar.gz"
libaom_archive="$download_dir/libaom-$LIBAOM_VERSION.tar.gz"
opus_archive="$download_dir/opus-$OPUS_VERSION.tar.gz"

download_and_verify "$FFMPEG_URL" "$FFMPEG_SHA256" "$ffmpeg_archive"
download_and_verify "$LIBVPX_URL" "$LIBVPX_SHA256" "$libvpx_archive"
download_and_verify "$LIBAOM_URL" "$LIBAOM_SHA256" "$libaom_archive"
download_and_verify "$OPUS_URL" "$OPUS_SHA256" "$opus_archive"

tar -xf "$ffmpeg_archive" -C "$source_dir"
tar -xf "$libvpx_archive" -C "$source_dir"
tar -xf "$libaom_archive" -C "$source_dir"
tar -xf "$opus_archive" -C "$source_dir"

ffmpeg_source="$source_dir/ffmpeg-$FFMPEG_VERSION"
libvpx_source="$source_dir/libvpx-$LIBVPX_VERSION"
libaom_source="$source_dir/libaom-$LIBAOM_VERSION"
opus_source="$source_dir/opus-$OPUS_VERSION"
opus_prefix="$prefix_dir/opus"
libvpx_prefix="$prefix_dir/libvpx"
libaom_prefix="$prefix_dir/libaom"

jobs="$(sysctl -n hw.ncpu)"
export MACOSX_DEPLOYMENT_TARGET=14.0
common_cflags="-arch arm64 -mmacosx-version-min=14.0 -O2"
common_ldflags="-arch arm64 -mmacosx-version-min=14.0"

(
  cd "$opus_source"
  ./configure \
    --prefix="$opus_prefix" \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --disable-extra-programs \
    CFLAGS="$common_cflags" \
    LDFLAGS="$common_ldflags"
  make -j"$jobs"
  make install
)

(
  cd "$libvpx_source"
  CFLAGS="$common_cflags" LDFLAGS="$common_ldflags" ./configure \
    --prefix="$libvpx_prefix" \
    --target=arm64-darwin23-gcc \
    --disable-shared \
    --enable-static \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests
  make -j"$jobs"
  make install
)

cmake \
  -S "$libaom_source" \
  -B "$build_root/libaom-build" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$libaom_prefix" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_DOCS=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_TOOLS=OFF
cmake --build "$build_root/libaom-build" --parallel "$jobs"
cmake --install "$build_root/libaom-build"

export PKG_CONFIG_PATH="$opus_prefix/lib/pkgconfig:$libvpx_prefix/lib/pkgconfig:$libaom_prefix/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
ffmpeg_configure=(
  --prefix="$tool_dir"
  --cc=clang
  --arch=arm64
  --target-os=darwin
  --enable-static
  --disable-shared
  --disable-debug
  --disable-doc
  --disable-ffplay
  --disable-network
  --disable-xlib
  --disable-libxcb
  --disable-libxcb-shm
  --disable-libxcb-shape
  --disable-libxcb-xfixes
  --disable-gpl
  --disable-nonfree
  --enable-libaom
  --enable-libvpx
  --enable-libopus
  --pkg-config-flags=--static
  --extra-cflags="$common_cflags -I$opus_prefix/include -I$libvpx_prefix/include -I$libaom_prefix/include"
  --extra-ldflags="$common_ldflags -L$opus_prefix/lib -L$libvpx_prefix/lib -L$libaom_prefix/lib"
)

(
  cd "$ffmpeg_source"
  ./configure "${ffmpeg_configure[@]}"
  make -j"$jobs"
  make install
)

cp "$ffmpeg_source/ffmpeg" "$tool_dir/bin/ffmpeg"
cp "$ffmpeg_source/ffprobe" "$tool_dir/bin/ffprobe"
chmod +x "$tool_dir/bin/ffmpeg" "$tool_dir/bin/ffprobe"

cp "$ffmpeg_archive" "$libvpx_archive" "$libaom_archive" "$opus_archive" "$source_offer/"
cp "$manifest" "$source_offer/versions.env"
cp "$ffmpeg_source/LICENSE.md" "$source_offer/FFmpeg-LICENSE.md"
cp "$ffmpeg_source/COPYING.LGPLv2.1" "$source_offer/FFmpeg-COPYING.LGPLv2.1"
cp "$ffmpeg_source/COPYING.LGPLv3" "$source_offer/FFmpeg-COPYING.LGPLv3"
cp "$libvpx_source/LICENSE" "$source_offer/libvpx-LICENSE"
cp "$libaom_source/LICENSE" "$source_offer/libaom-LICENSE"
cp "$opus_source/COPYING" "$source_offer/Opus-COPYING"

{
  print "Convert Anything reproducible media tool build"
  print ""
  print "Source archives are the unmodified release archives listed in Dependencies/ffmpeg/versions.env."
  print "No patches are applied; the git-diff equivalent against each extracted archive is empty."
  print "All archive SHA-256 values are verified before extraction."
  print ""
  print "FFmpeg configure:"
  print -r -- "./configure ${(j: :)ffmpeg_configure}"
  print ""
  print "Deployment target: macOS 14.0"
  print "Architecture: arm64"
} > "$source_offer/BUILD.txt"

file "$tool_dir/bin/ffmpeg"
file "$tool_dir/bin/ffprobe"
print "Built verified media tools: $tool_dir/bin"
