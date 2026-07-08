#!/usr/bin/env sh
set -eu

CONFIGURATION_NAME="${1:-Debug}"
SDK_NAME="${2:-iphonesimulator}"
IOS_PROJECT_DIR="${3:-}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CRATE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -n "$IOS_PROJECT_DIR" ]; then
  IOS_DIR="$IOS_PROJECT_DIR"
else
  IOS_DIR="$(CDPATH= cd -- "$CRATE_DIR/../../ios" && pwd)"
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "Perl is required to build vendored OpenSSL for iOS. Install perl and ensure it is on PATH." >&2
  exit 1
fi
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
  if command -v sysctl >/dev/null 2>&1; then
    cores="$(sysctl -n hw.logicalcpu 2>/dev/null || printf '1')"
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

config_lower="$(printf '%s' "$CONFIGURATION_NAME" | tr '[:upper:]' '[:lower:]')"
PROFILE="debug"
if [ "$config_lower" = "release" ] || [ "$config_lower" = "profile" ]; then
  PROFILE="release"
fi

OUTPUT_DIR="$IOS_DIR/Flutter/Polarmote_native/$CONFIGURATION_NAME/$SDK_NAME"
OUTPUT_LIB="$OUTPUT_DIR/libPolarmote_native_core.a"
mkdir -p "$OUTPUT_DIR"

LATEST_INPUT_TS=0
update_latest_ts "$CRATE_DIR/Cargo.toml"
update_latest_ts "$CRATE_DIR/Cargo.lock"
update_latest_ts "$SCRIPT_DIR/build_ios_lib.sh"
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

export CARGO_INCREMENTAL=1
export Polarmote_BUILD_ID="$LATEST_INPUT_TS"
export Polarmote_BUILD_PROFILE="$PROFILE"
enable_sccache_if_available
configure_parallel_jobs

build_target_if_needed() {
  target="$1"
  if ! is_target_installed "$target"; then
    rustup target add "$target" >/dev/null 2>&1 || true
  fi
  lib_path="$CRATE_DIR/target/$target/$PROFILE/libPolarmote_native_core.a"
  needs_build=1
  if [ -f "$lib_path" ]; then
    built_ts="$(stat_mtime "$lib_path")"
    if [ "$built_ts" -ge "$LATEST_INPUT_TS" ]; then
      needs_build=0
    fi
  fi
  if [ "$needs_build" -eq 1 ]; then
    if [ "$PROFILE" = "release" ]; then
      cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --target "$target" --release
    else
      cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --target "$target"
    fi
  else
    echo "Skipping Rust iOS target $target ($PROFILE): artifact is up to date."
  fi
  if [ ! -f "$lib_path" ]; then
    echo "Rust iOS artifact not found: $lib_path" >&2
    exit 1
  fi
}

if [ "$SDK_NAME" = "iphoneos" ]; then
  build_target_if_needed "aarch64-apple-ios"
  cp "$CRATE_DIR/target/aarch64-apple-ios/$PROFILE/libPolarmote_native_core.a" "$OUTPUT_LIB"
else
  sim_targets=""
  if [ "${Polarmote_IOS_SIM_UNIVERSAL:-0}" = "1" ]; then
    sim_targets="aarch64-apple-ios-sim x86_64-apple-ios"
  else
    host_arch="$(uname -m)"
    if [ "$host_arch" = "arm64" ]; then
      sim_targets="aarch64-apple-ios-sim"
    else
      sim_targets="x86_64-apple-ios"
    fi
  fi

  for target in $sim_targets; do
    build_target_if_needed "$target"
  done

  lib_arm64="$CRATE_DIR/target/aarch64-apple-ios-sim/$PROFILE/libPolarmote_native_core.a"
  lib_x86_64="$CRATE_DIR/target/x86_64-apple-ios/$PROFILE/libPolarmote_native_core.a"

  if [ "$sim_targets" = "aarch64-apple-ios-sim x86_64-apple-ios" ] && [ -f "$lib_arm64" ] && [ -f "$lib_x86_64" ]; then
    lipo -create "$lib_arm64" "$lib_x86_64" -output "$OUTPUT_LIB"
  elif printf '%s' "$sim_targets" | grep -Fq "aarch64-apple-ios-sim"; then
    cp "$lib_arm64" "$OUTPUT_LIB"
  elif printf '%s' "$sim_targets" | grep -Fq "x86_64-apple-ios"; then
    cp "$lib_x86_64" "$OUTPUT_LIB"
  else
    echo "No simulator Rust iOS artifact found." >&2
    exit 1
  fi
fi

echo "Rust iOS library prepared: $OUTPUT_LIB"
