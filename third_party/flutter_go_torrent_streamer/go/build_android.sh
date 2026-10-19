#!/usr/bin/env bash
set -euo pipefail

# Requires Go 1.23.6 and Android NDK 27.2.12479018 (API 21).
script_dir=$(cd "$(dirname "$0")" && pwd)
ndk_version=27.2.12479018
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
ndk=${ANDROID_NDK_HOME:-${sdk:+$sdk/ndk/$ndk_version}}
if [[ -z "$ndk" || ! -d "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
  echo "Android NDK $ndk_version required: set ANDROID_HOME or ANDROID_NDK_HOME" >&2
  exit 1
fi
if [[ $(go version) != *'go1.23.6 '* ]]; then
  echo 'Go 1.23.6 required' >&2
  exit 1
fi
bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
out="$script_dir/../android/src/main/jniLibs"
cd "$script_dir"
for target in arm64-v8a:arm64:aarch64 x86_64:amd64:x86_64; do
  IFS=: read -r abi arch triple <<< "$target"
  mkdir -p "$out/$abi"
  cc="$bin/${triple}-linux-android21-clang"
  cxx="$bin/${triple}-linux-android21-clang++"
  [[ -x "$cc" && -x "$cxx" ]] || {
    echo "Missing Android compiler: CC=$cc CXX=$cxx" >&2
    exit 1
  }
  env GOOS=android GOARCH="$arch" CGO_ENABLED=1 CC="$cc" CXX="$cxx" \
    go build -x -trimpath -buildmode=c-shared -o "$out/$abi/libtorrent_streamer.so" .
  cxx_runtime="$ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/${triple}-linux-android/libc++_shared.so"
  [[ -f "$cxx_runtime" ]] || {
    echo "Missing Android C++ runtime: $cxx_runtime" >&2
    exit 1
  }
  cp "$cxx_runtime" "$out/$abi/libc++_shared.so"
  symbols=$(mktemp)
  "$bin/llvm-nm" -D "$out/$abi/libtorrent_streamer.so" > "$symbols"
  grep -Eq ' [T] StartStream$' "$symbols"
  grep -Eq ' [T] GetStreamStatus$' "$symbols"
  rm -f "$symbols"
done
