use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    let manifest_dir = match env::var("CARGO_MANIFEST_DIR") {
        Ok(value) => PathBuf::from(value),
        Err(_) => return,
    };

    let mut tracked_files = Vec::new();
    let src_dir = manifest_dir.join("src");
    collect_rust_files(&src_dir, &mut tracked_files);

    let cargo_toml = manifest_dir.join("Cargo.toml");
    if cargo_toml.exists() {
        tracked_files.push(cargo_toml);
    }
    let build_script = manifest_dir.join("build.rs");
    if build_script.exists() {
        tracked_files.push(build_script);
    }

    let mut latest_mtime = UNIX_EPOCH;
    for path in &tracked_files {
        if let Ok(metadata) = fs::metadata(path) {
            if let Ok(modified) = metadata.modified() {
                if modified > latest_mtime {
                    latest_mtime = modified;
                }
            }
        }
        if let Ok(relative) = path.strip_prefix(&manifest_dir) {
            println!("cargo:rerun-if-changed={}", relative.to_string_lossy());
        } else {
            println!("cargo:rerun-if-changed={}", path.to_string_lossy());
        }
    }

    let latest_seconds = latest_mtime
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|value| value.as_secs())
        .unwrap_or_else(now_unix_seconds);

    let pkg_version = env::var("CARGO_PKG_VERSION").unwrap_or_else(|_| "0.0.0".to_owned());
    let engine_version = format!("{pkg_version}+src.{latest_seconds}");
    println!("cargo:rustc-env=ASMOTE_ENGINE_VERSION={engine_version}");
}

fn collect_rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let read_dir = match fs::read_dir(dir) {
        Ok(value) => value,
        Err(_) => return,
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_rust_files(&path, out);
            continue;
        }
        if path.extension().is_some_and(|value| value == "rs") {
            out.push(path);
        }
    }
}

fn now_unix_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|value| value.as_secs())
        .unwrap_or(0)
}
