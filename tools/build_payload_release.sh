#!/usr/bin/env bash
set -euo pipefail

# Portable release builder for Root-My-Galaxy-Payloads app payloads.
# Usage:
#   ./tools/build_payload_release.sh [TARGET] [ANDROID_NDK_HOME]
# Examples:
#   ./tools/build_payload_release.sh e1q-S9210ZCS6DZF2 /Users/jiyuren/Library/Android/sdk/ndk/27.1.12297006
#   TARGET=e1q-S9210ZCS6DZF2 ANDROID_NDK_HOME=/path/to/android-ndk ./tools/build_payload_release.sh

TARGET="${1:-${TARGET:-e1q-S9210ZCS6DZF2}}"
NDK_HOME="${2:-${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}}"
API="${API:-35}"
RELEASE_SIZE="${APP_RELEASE_SIZE:-104128}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="${OUTDIR:-$ROOT_DIR/build/$TARGET}"
ARTIFACT_DIR="$ROOT_DIR/artifacts/$TARGET"
TARGET_HEADER="$ROOT_DIR/src/targets/$TARGET/target.h"
TARGET_INCLUDE="targets/$TARGET/target.h"
APP_RELEASE="$OUTDIR/cve-2026-43499-app.release.so"
ARTIFACT="$ARTIFACT_DIR/cve-2026-43499-app.so"

fail() {
  echo "error: $*" >&2
  exit 1
}

host_tag() {
  case "$(uname -s)" in
    Darwin) echo "darwin-x86_64" ;;
    Linux) echo "linux-x86_64" ;;
    *) fail "unsupported host OS: $(uname -s)" ;;
  esac
}

find_clang() {
  if [[ -n "${TARGET_CC:-}" && -x "${TARGET_CC:-}" ]]; then
    echo "$TARGET_CC"
    return
  fi

  local host
  host="$(host_tag)"
  if [[ -n "$NDK_HOME" ]]; then
    local cc="$NDK_HOME/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android${API}-clang"
    [[ -x "$cc" ]] && { echo "$cc"; return; }
  fi

  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -n "$sdk" && -d "$sdk/ndk" ]]; then
    local cc
    cc="$(find "$sdk/ndk" -path "*/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android${API}-clang" -type f 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "$cc" && -x "$cc" ]] && { echo "$cc"; return; }
  fi

  fail "cannot find aarch64-linux-android${API}-clang; pass ANDROID_NDK_HOME or TARGET_CC"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "sha256-tool-missing"
  fi
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

[[ -f "$TARGET_HEADER" ]] || fail "missing target header: $TARGET_HEADER"

TARGET_CC_RESOLVED="$(find_clang)"
mkdir -p "$OUTDIR" "$ARTIFACT_DIR"

SRCS=(
  "$ROOT_DIR/src/main.c"
  "$ROOT_DIR/src/util.c"
  "$ROOT_DIR/src/slide_app.c"
  "$ROOT_DIR/src/fops.c"
  "$ROOT_DIR/src/pipe.c"
  "$ROOT_DIR/src/root.c"
  "$ROOT_DIR/src/preload.c"
)

printf 'target: %s\n' "$TARGET"
printf 'compiler: %s\n' "$TARGET_CC_RESOLVED"
printf 'output: %s\n' "$APP_RELEASE"

"$TARGET_CC_RESOLVED" \
  -DAPP_PAYLOAD=1 -fPIC -Oz -g0 \
  -fno-unwind-tables -fno-asynchronous-unwind-tables \
  -ffunction-sections -fdata-sections \
  -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare \
  -I"$ROOT_DIR/src" -DTARGET_HEADER="\"$TARGET_INCLUDE\"" \
  "${SRCS[@]}" -shared -pthread \
  -Wl,--gc-sections -Wl,--icf=all -s -o "$APP_RELEASE"

UNPADDED_SIZE="$(file_size "$APP_RELEASE")"
printf 'unpad_size: %s\n' "$UNPADDED_SIZE"
if (( UNPADDED_SIZE > RELEASE_SIZE )); then
  fail "release output is larger than fixed size: $UNPADDED_SIZE > $RELEASE_SIZE"
fi

truncate -s "$RELEASE_SIZE" "$APP_RELEASE"
cp "$APP_RELEASE" "$ARTIFACT"

FINAL_SIZE="$(file_size "$ARTIFACT")"
FINAL_SHA256="$(sha256_file "$ARTIFACT")"
[[ "$FINAL_SIZE" == "$RELEASE_SIZE" ]] || fail "artifact size mismatch: $FINAL_SIZE != $RELEASE_SIZE"

printf 'artifact: %s\n' "$ARTIFACT"
printf 'size: %s\n' "$FINAL_SIZE"
printf 'sha256: %s\n' "$FINAL_SHA256"
file "$ARTIFACT"
