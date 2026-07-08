#!/usr/bin/env sh
set -eu

CRATE_DIR=""
OUTPUT_DIR=""
NDK_DIR=""
PROFILE="debug"
API_LEVEL="21"
ABIS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --crate-dir)
      CRATE_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --ndk-dir)
      NDK_DIR="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --api-level)
      API_LEVEL="$2"
      shift 2
      ;;
    --abis)
      ABIS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$CRATE_DIR" ] || [ -z "$OUTPUT_DIR" ] || [ -z "$NDK_DIR" ]; then
  echo "Missing required arguments." >&2
  exit 2
fi

if [ ! -d "$CRATE_DIR" ]; then
  echo "Crate directory not found: $CRATE_DIR" >&2
  exit 1
fi
if [ ! -d "$NDK_DIR" ]; then
  echo "Android NDK directory not found: $NDK_DIR" >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "Perl is required to build vendored OpenSSL for Android. Install perl and ensure it is on PATH." >&2
  exit 1
fi
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PERL_SHIM_DIR="$SCRIPT_DIR/perl_lib"
if ! perl -MLocale::Maketext::Simple -MExtUtils::MakeMaker -e 1 >/dev/null 2>&1; then
  if [ -f "$PERL_SHIM_DIR/Locale/Maketext/Simple.pm" ]; then
    if [ -n "${PERL5LIB:-}" ]; then
      export PERL5LIB="$PERL_SHIM_DIR:$PERL5LIB"
    else
      export PERL5LIB="$PERL_SHIM_DIR"
    fi
  fi
fi
if ! perl -MLocale::Maketext::Simple -MExtUtils::MakeMaker -e 1 >/dev/null 2>&1; then
  echo "Perl is missing Locale::Maketext::Simple/ExtUtils::MakeMaker and shim was not enough." >&2
  exit 1
fi

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

stat_mtime() {
  file="$1"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
    return
  fi
  stat -f %m "$file"
}

update_latest_ts() {
  file="$1"
  if [ ! -f "$file" ]; then
    return
  fi
  ts="$(stat_mtime "$file")"
  if [ "$ts" -gt "$LATEST_INPUT_TS" ]; then
    LATEST_INPUT_TS="$ts"
  fi
}

enable_sccache_if_available() {
  if command -v sccache >/dev/null 2>&1; then
    export RUSTC_WRAPPER="sccache"
    sccache --start-server >/dev/null 2>&1 || true
    echo "Using sccache for Rust compilation."
  fi
}

configure_parallel_jobs() {
  if command -v getconf >/dev/null 2>&1; then
    cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
  else
    cores="1"
  fi
  case "$cores" in
    ''|*[!0-9]*)
      cores="1"
      ;;
  esac
  if [ "$cores" -gt 1 ]; then
    export CARGO_BUILD_JOBS="$((cores - 1))"
  fi
}

is_target_installed() {
  target="$1"
  rustup target list --installed 2>/dev/null | grep -Fxq "$target"
}

target_requested() {
  abi="$1"
  if [ -z "$ABIS" ]; then
    return 0
  fi
  abi_csv=",$ABIS,"
  case "$abi_csv" in
    *",$abi,"*) return 0 ;;
  esac
  return 1
}

find_toolchain_bin() {
  case "$HOST_OS" in
    Linux)
      echo "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
      return
      ;;
    Darwin)
      if [ "$HOST_ARCH" = "arm64" ] && [ -d "$NDK_DIR/toolchains/llvm/prebuilt/darwin-arm64/bin" ]; then
        echo "$NDK_DIR/toolchains/llvm/prebuilt/darwin-arm64/bin"
        return
      fi
      echo "$NDK_DIR/toolchains/llvm/prebuilt/darwin-x86_64/bin"
      return
      ;;
  esac
  echo ""
}

TOOLCHAIN_BIN="$(find_toolchain_bin)"
if [ -z "$TOOLCHAIN_BIN" ] || [ ! -d "$TOOLCHAIN_BIN" ]; then
  echo "Android NDK llvm toolchain not found for host: $HOST_OS/$HOST_ARCH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
export CARGO_INCREMENTAL=1
enable_sccache_if_available
configure_parallel_jobs

LATEST_INPUT_TS=0
update_latest_ts "$CRATE_DIR/Cargo.toml"
update_latest_ts "$CRATE_DIR/Cargo.lock"
update_latest_ts "$SCRIPT_DIR/build_android_libs.sh"
if [ -d "$CRATE_DIR/src" ]; then
  while IFS= read -r source_file; do
    [ -z "$source_file" ] && continue
    update_latest_ts "$source_file"
  done <<EOF
$(find "$CRATE_DIR/src" -type f -name '*.rs')
EOF
fi
if [ -d "$CRATE_DIR/.cargo" ]; then
  while IFS= read -r config_file; do
    [ -z "$config_file" ] && continue
    update_latest_ts "$config_file"
  done <<EOF
$(find "$CRATE_DIR/.cargo" -type f)
EOF
fi
if [ -d "$SCRIPT_DIR/perl_lib" ]; then
  while IFS= read -r perl_file; do
    [ -z "$perl_file" ] && continue
    update_latest_ts "$perl_file"
  done <<EOF
$(find "$SCRIPT_DIR/perl_lib" -type f)
EOF
fi

export Polarmote_BUILD_ID="$LATEST_INPUT_TS"
export Polarmote_BUILD_PROFILE="$PROFILE"

build_target() {
  triple="$1"
  abi="$2"
  clang_prefix="$3"

  if ! target_requested "$abi"; then
    echo "Skipping Android ABI $abi (not selected in --abis)."
    return
  fi

  linker="$TOOLCHAIN_BIN/${clang_prefix}${API_LEVEL}-clang"
  if [ ! -x "$linker" ]; then
    echo "NDK linker not found: $linker" >&2
    exit 1
  fi

  cargo_env_suffix="$(printf '%s' "$triple" | tr '[:lower:]-' '[:upper:]_')"
  cc_env_suffix="$(printf '%s' "$triple" | tr '-' '_')"
  eval "export CARGO_TARGET_${cargo_env_suffix}_LINKER=\"$linker\""
  eval "export CC_${cc_env_suffix}=\"$linker\""
  eval "export AR_${cc_env_suffix}=\"$TOOLCHAIN_BIN/llvm-ar\""
  eval "export RANLIB_${cc_env_suffix}=\"$TOOLCHAIN_BIN/llvm-ranlib\""
  export PATH="$TOOLCHAIN_BIN:$PATH"

  if ! is_target_installed "$triple"; then
    rustup target add "$triple" >/dev/null
  fi
  lib_path="$CRATE_DIR/target/$triple/$PROFILE/libPolarmote_native_core.so"
  abi_dir="$OUTPUT_DIR/$abi"
  output_lib="$abi_dir/libPolarmote_native_core.so"

  needs_build=1
  # Accept either the target dir artifact or the already-copied output
  if [ -f "$output_lib" ]; then
    built_ts="$(stat_mtime "$output_lib")"
    if [ "$built_ts" -ge "$LATEST_INPUT_TS" ]; then
      needs_build=0
    fi
  elif [ -f "$lib_path" ]; then
    built_ts="$(stat_mtime "$lib_path")"
    if [ "$built_ts" -ge "$LATEST_INPUT_TS" ]; then
      needs_build=0
    fi
  fi

  if [ "$needs_build" -eq 1 ]; then
    if [ "$PROFILE" = "release" ]; then
      cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --target "$triple" --release
    else
      cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --target "$triple"
    fi
  else
    echo "Skipping Rust target $triple ($PROFILE): artifact is up to date."
  fi

  if [ -f "$lib_path" ]; then
    mkdir -p "$abi_dir"
    needs_copy=1
    if [ -f "$output_lib" ]; then
      src_ts="$(stat_mtime "$lib_path")"
      dst_ts="$(stat_mtime "$output_lib")"
      if [ "$src_ts" -le "$dst_ts" ]; then
        needs_copy=0
      fi
    fi
    if [ "$needs_copy" -eq 1 ]; then
      cp "$lib_path" "$output_lib"
    fi
  elif [ ! -f "$output_lib" ]; then
    echo "Rust Android artifact not found: $lib_path" >&2
    exit 1
  fi
}

if [ -n "$ABIS" ]; then
  selected_count=0
  OLD_IFS="$IFS"
  IFS=','
  for requested in $ABIS; do
    IFS="$OLD_IFS"
    trimmed="$(printf '%s' "$requested" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$trimmed" in
      arm64-v8a|armeabi-v7a|x86_64)
        selected_count=$((selected_count + 1))
        ;;
      "")
        ;;
      *)
        echo "Unsupported ABI in --abis: $trimmed" >&2
        exit 2
        ;;
    esac
    IFS=','
  done
  IFS="$OLD_IFS"
  if [ "$selected_count" -eq 0 ]; then
    echo "No valid ABI selected in --abis." >&2
    exit 2
  fi
  echo "Building selected Android ABIs: $ABIS"
fi

build_target "aarch64-linux-android" "arm64-v8a" "aarch64-linux-android"
build_target "armv7-linux-androideabi" "armeabi-v7a" "armv7a-linux-androideabi"
build_target "x86_64-linux-android" "x86_64" "x86_64-linux-android"

echo "Rust Android libraries prepared in: $OUTPUT_DIR"
