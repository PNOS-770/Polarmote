#!/usr/bin/env sh
set -eu

CRATE_DIR=""
OUTPUT_DIR=""
PROFILE="debug"
PLATFORM=""

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
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$CRATE_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Missing required arguments." >&2
  exit 2
fi
if [ -z "$PLATFORM" ]; then
  uname_s="$(uname -s)"
  case "$uname_s" in
    Linux) PLATFORM="linux" ;;
    Darwin) PLATFORM="macos" ;;
    *)
      echo "Unsupported desktop host: $uname_s" >&2
      exit 2
      ;;
  esac
fi

if [ ! -d "$CRATE_DIR" ]; then
  echo "Crate directory not found: $CRATE_DIR" >&2
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "Rust toolchain is required but cargo was not found in PATH." >&2
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

resolve_artifact_name() {
  case "$1" in
    windows) printf "asmote_native_core.dll" ;;
    linux) printf "libasmote_native_core.so" ;;
    macos) printf "libasmote_native_core.dylib" ;;
    *)
      echo "Unsupported platform: $1" >&2
      exit 2
      ;;
  esac
}

mkdir -p "$OUTPUT_DIR"
export CARGO_INCREMENTAL=1
enable_sccache_if_available
configure_parallel_jobs

LATEST_INPUT_TS=0
update_latest_ts "$CRATE_DIR/Cargo.toml"
update_latest_ts "$CRATE_DIR/Cargo.lock"
update_latest_ts "$0"
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
if [ -d "$CRATE_DIR/scripts" ]; then
  while IFS= read -r script_file; do
    [ -z "$script_file" ] && continue
    update_latest_ts "$script_file"
  done <<EOF
$(find "$CRATE_DIR/scripts" -type f)
EOF
fi

artifact_name="$(resolve_artifact_name "$PLATFORM")"
export ASMOTE_BUILD_ID="$LATEST_INPUT_TS"
export ASMOTE_BUILD_PROFILE="$PROFILE"
source_artifact="$CRATE_DIR/target/$PROFILE/$artifact_name"
output_artifact="$OUTPUT_DIR/$artifact_name"

needs_build=1
if [ -f "$source_artifact" ]; then
  built_ts="$(stat_mtime "$source_artifact")"
  if [ "$built_ts" -ge "$LATEST_INPUT_TS" ]; then
    needs_build=0
  fi
fi

if [ "$needs_build" -eq 1 ]; then
  echo "Building Rust desktop core ($PLATFORM/$PROFILE)..."
  if [ "$PROFILE" = "release" ]; then
    cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release
  else
    cargo build --manifest-path "$CRATE_DIR/Cargo.toml"
  fi
else
  echo "Skipping Rust desktop build ($PLATFORM/$PROFILE): artifact is up to date."
fi

if [ ! -f "$source_artifact" ]; then
  echo "Rust desktop artifact not found: $source_artifact" >&2
  exit 1
fi

needs_copy=1
if [ -f "$output_artifact" ]; then
  src_ts="$(stat_mtime "$source_artifact")"
  dst_ts="$(stat_mtime "$output_artifact")"
  if [ "$src_ts" -le "$dst_ts" ]; then
    needs_copy=0
  fi
fi
if [ "$needs_copy" -eq 1 ]; then
  cp "$source_artifact" "$output_artifact"
fi

echo "Rust desktop library prepared: $output_artifact"
