# Polarmote Native Transfer Core

Rust implementation of the transfer core defined in `docs/chuanshu.md`.

## ABI

Exported C ABI symbols:

- `Polarmote_create_session(config_json)`
- `Polarmote_destroy_session(session_id)`
- `Polarmote_enqueue_transfer(session_id, task_json)`
- `Polarmote_cancel_task(session_id, task_id)`
- `Polarmote_query_progress(session_id, task_id)`
- `Polarmote_poll_events(session_id)`
- `Polarmote_free_c_string(ptr)`

## Build (Desktop)

```powershell
cargo build
cargo build --release
```

### Desktop Backend Note

RDP backend code has been removed from native core. Desktop build now only
contains transfer/session/PTY runtime symbols.

Artifacts:

- Windows: `target/<profile>/Polarmote_native_core.dll`
- Linux: `target/<profile>/libPolarmote_native_core.so`
- macOS: `target/<profile>/libPolarmote_native_core.dylib`

## Build (Mobile)

Android example:

```powershell
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo build --release --target aarch64-linux-android
cargo build --release --target armv7-linux-androideabi
cargo build --release --target x86_64-linux-android
```

iOS example:

```powershell
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
```

Dart side uses runtime dynamic loading. Rust native transport core is required; when the library is missing, transfers fail with an explicit error.

## Mobile Integration In This Repo

### Android

`android/app/build.gradle.kts` now wires Rust build into `preBuild`:

- Build script: `native/Polarmote_native_core/scripts/build_android_libs.ps1` (Windows)
- Build script: `native/Polarmote_native_core/scripts/build_android_libs.sh` (macOS/Linux)
- Output directory: `android/app/build/generated/rustJniLibs/<abi>/libPolarmote_native_core.so`
- ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- Incremental behavior:
  - Gradle task declares Rust source/manifests as inputs and `rustJniLibs` as outputs.
  - Build scripts skip unchanged ABI artifacts (timestamp-based) and only copy updated `.so`.
  - `CARGO_INCREMENTAL=1` is enabled to improve local debug iteration speed.
  - If `sccache` is available on PATH, it is auto-enabled for Rust compile cache.
  - `CARGO_BUILD_JOBS` is auto-tuned to `logical_cpus - 1`.

Optional fast local debug knobs:

- Build only specific ABIs (greatly reduces Android debug build time):
  - Environment variable: `Polarmote_ANDROID_ABIS=x86_64`
  - Or Gradle property: `-PPolarmoteRustAbis=x86_64`
  - Supported values: `arm64-v8a`, `armeabi-v7a`, `x86_64` (comma-separated supported)

Prerequisites:

1. Rust + Cargo + rustup are installed.
2. Android SDK + NDK are installed.
3. `rustup` can add Android targets.
4. Perl is available for vendored OpenSSL build.
   - Android on Windows needs a non-`MSWin32` perl (`msys` perl, e.g. Git for Windows perl).
   - If `Locale::Maketext::Simple` / `ExtUtils::MakeMaker` are missing, scripts auto-load shim from
     `native/Polarmote_native_core/scripts/perl_lib`.
   - Strawberry Perl alone cannot be used for Android OpenSSL configure on Windows path semantics.
5. `make` is available.
   - On Windows, script auto-shims `make` from `C:\Strawberry\c\bin\gmake.exe` when available.
6. Windows path encoding:
   - If detected rust sysroot contains non-ASCII characters, script auto-switches to
     project-local Rustup/Cargo homes under `native/Polarmote_native_core/.rustup-local` and
     `native/Polarmote_native_core/.cargo-local`.

Skip Rust Android build temporarily:

```powershell
set Polarmote_SKIP_RUST_ANDROID=1
```

### iOS

`ios/Runner.xcodeproj/project.pbxproj` now includes a build phase:

- Build phase name: `Build Rust Native Core`
- Script: `native/Polarmote_native_core/scripts/build_ios_lib.sh`
- Linked output: `ios/Flutter/Polarmote_native/<CONFIGURATION>/<SDK_NAME>/libPolarmote_native_core.a`

The script builds Rust static libraries for iOS targets and links with:

- `-force_load $(PROJECT_DIR)/Flutter/Polarmote_native/$(CONFIGURATION)/$(SDK_NAME)/libPolarmote_native_core.a`

Prerequisites:

1. Build on macOS with Xcode command line tools.
2. Rust targets available for iOS (`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`).
3. Perl runtime is available on PATH.
   - If `Locale::Maketext::Simple` / `ExtUtils::MakeMaker` are missing, scripts auto-load shim from `scripts/perl_lib`.

Build speed behavior:

- iOS script is incremental (skips unchanged Rust artifacts).
- Simulator default:
  - Apple Silicon host: only `aarch64-apple-ios-sim`
  - Intel host: only `x86_64-apple-ios`
- Force universal simulator lib (slower):
  - `Polarmote_IOS_SIM_UNIVERSAL=1`

## Desktop Incremental Build

Desktop packaging now uses script-based incremental Rust build:

- Windows script: `native/Polarmote_native_core/scripts/build_desktop_libs.ps1`
- Linux/macOS script: `native/Polarmote_native_core/scripts/build_desktop_libs.sh`

Behavior:

- Skip `cargo build` when Rust inputs are unchanged.
- Copy artifact only when newer.
- Auto-enable `sccache` when available.

## Troubleshooting

- Error `Rust native transport core is not available`:
  - Confirm mobile artifact exists for current ABI/SDK.
  - Rebuild app and check Rust build script output logs.
- Android linker/toolchain errors:
  - Verify NDK installation path and version resolved by Gradle.
- iOS symbol missing errors:
  - Verify `Build Rust Native Core` phase runs before link.
  - Confirm output static library exists under `ios/Flutter/Polarmote_native/...`.
