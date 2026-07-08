use crate::error::{CoreError, CoreResult};
use crate::models::{SessionConfig, TaskExecutionOutput};
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine;
use libssh_rs::{AuthStatus, FileType, OpenFlags, Session, Sftp, SshOption};
use serde::{Deserialize, Serialize};
use std::fs::{self, create_dir_all, File as LocalFile};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub struct SftpConnection {
    _session: Session,
    sftp: Sftp,
    resume_enabled: bool,
}

impl SftpConnection {
    pub fn connect(config: &SessionConfig) -> CoreResult<Self> {
        match Self::connect_with_profile(config, false) {
            Ok(connection) => Ok(connection),
            Err(primary_err) => {
                if should_retry_with_compatibility(&primary_err) {
                    match Self::connect_with_profile(config, true) {
                        Ok(connection) => Ok(connection),
                        Err(compat_err) => Err(CoreError::Ssh(format!(
                            "ssh handshake failed (profile=balanced): {primary_err}; retry with handshake profile 'compatibility' also failed: {compat_err}"
                        ))),
                    }
                } else {
                    Err(primary_err)
                }
            }
        }
    }

    fn connect_with_profile(
        config: &SessionConfig,
        compatibility_profile: bool,
    ) -> CoreResult<Self> {
        let session = Session::new()?;
        session.set_option(SshOption::Hostname(config.host.clone()))?;
        session.set_option(SshOption::Port(config.port_or_default()))?;
        session.set_option(SshOption::User(Some(config.username.clone())))?;
        session.set_option(SshOption::Timeout(config.connect_timeout()))?;

        if compatibility_profile {
            apply_compatibility_handshake_profile(&session)?;
        }

        if let Some(private_key_path) = &config.private_key_path {
            session.set_option(SshOption::AddIdentity(private_key_path.clone()))?;
        }

        session.connect()?;
        session.set_option(SshOption::Timeout(config.io_timeout()))?;

        authenticate(&session, config)?;

        let sftp = session.sftp()?;
        Ok(Self {
            _session: session,
            sftp,
            resume_enabled: config.enable_resume(),
        })
    }

    pub fn sftp(&self) -> &Sftp {
        &self.sftp
    }

    pub fn resume_enabled(&self) -> bool {
        self.resume_enabled
    }
}

fn should_retry_with_compatibility(error: &CoreError) -> bool {
    match error {
        CoreError::Ssh(message) => {
            let lower = message.to_ascii_lowercase();
            lower.contains("exchange encryption keys")
                || lower.contains("key exchange")
                || lower.contains("kex")
                || lower.contains("handshake")
        }
        _ => false,
    }
}

fn apply_compatibility_handshake_profile(session: &Session) -> CoreResult<()> {
    // Legacy servers may only provide older algorithm sets.
    session.set_option(SshOption::KeyExchange(
        "curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha256,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1".to_string(),
    ))?;
    session.set_option(SshOption::HostKeys(
        "ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256,ssh-rsa,ssh-dss".to_string(),
    ))?;
    session.set_option(SshOption::PublicKeyAcceptedTypes(
        "ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256,ssh-rsa,ssh-dss".to_string(),
    ))?;
    session.set_option(SshOption::CiphersCS(
        "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,aes256-cbc,aes128-cbc,3des-cbc".to_string(),
    ))?;
    session.set_option(SshOption::CiphersSC(
        "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr,aes256-cbc,aes128-cbc,3des-cbc".to_string(),
    ))?;
    session.set_option(SshOption::HmacCS(
        "hmac-sha2-512,hmac-sha2-256,hmac-sha1,hmac-md5".to_string(),
    ))?;
    session.set_option(SshOption::HmacSC(
        "hmac-sha2-512,hmac-sha2-256,hmac-sha1,hmac-md5".to_string(),
    ))?;
    Ok(())
}

fn authenticate(session: &Session, config: &SessionConfig) -> CoreResult<()> {
    let mut attempted = false;

    if config.private_key_path.is_some() || config.password.is_none() {
        attempted = true;
        let passphrase = config
            .private_key_passphrase
            .as_deref()
            .or(config.password.as_deref());
        let status = session.userauth_public_key_auto(None, passphrase)?;
        if matches!(status, AuthStatus::Success) {
            return Ok(());
        }
    }

    if let Some(password) = config.password.as_deref() {
        attempted = true;
        let status = session.userauth_password(None, Some(password))?;
        if matches!(status, AuthStatus::Success) {
            return Ok(());
        }
    }

    if attempted {
        Err(CoreError::AuthenticationFailed)
    } else {
        Err(CoreError::Ssh(
            "no supported authentication method configured".to_string(),
        ))
    }
}

fn ensure_not_cancelled(cancelled: &AtomicBool) -> CoreResult<()> {
    if cancelled.load(Ordering::Relaxed) {
        return Err(CoreError::Cancelled);
    }
    Ok(())
}

fn normalize_remote_path(path: &str) -> String {
    let mut normalized = path.replace('\\', "/");
    while normalized.contains("//") {
        normalized = normalized.replace("//", "/");
    }
    if normalized.len() > 1 {
        normalized = normalized.trim_end_matches('/').to_string();
    }
    if normalized.is_empty() {
        "/".to_string()
    } else {
        normalized
    }
}

fn remote_parent(path: &str) -> Option<String> {
    let path = normalize_remote_path(path);
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() || trimmed == "/" {
        return None;
    }

    match trimmed.rfind('/') {
        Some(0) => Some("/".to_string()),
        Some(index) => Some(trimmed[..index].to_string()),
        None => None,
    }
}

fn join_remote_path(base: &str, child: &str) -> String {
    let base = normalize_remote_path(base);
    let child = child.replace('\\', "/");
    let child = child.trim_matches('/');
    if child.is_empty() {
        return base;
    }

    if base == "/" {
        format!("/{child}")
    } else {
        format!("{}/{}", base.trim_end_matches('/'), child)
    }
}

fn remote_basename(path: &str) -> Option<String> {
    let path = normalize_remote_path(path);
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() || trimmed == "/" {
        return None;
    }
    trimmed
        .rsplit('/')
        .next()
        .map(str::trim)
        .filter(|segment| !segment.is_empty())
        .map(str::to_string)
}

fn ensure_remote_directory_exists(sftp: &Sftp, dir: &str) -> CoreResult<()> {
    let dir = normalize_remote_path(dir);
    if dir.is_empty() || dir == "/" || dir == "." {
        return Ok(());
    }

    let absolute = dir.starts_with('/');
    let mut current = if absolute {
        "/".to_string()
    } else {
        String::new()
    };

    for segment in dir.split('/').filter(|part| !part.is_empty()) {
        if current.is_empty() {
            current.push_str(segment);
        } else if current == "/" {
            current.push_str(segment);
        } else {
            current.push('/');
            current.push_str(segment);
        }

        if sftp.metadata(&current).is_ok() {
            continue;
        }

        if sftp.create_dir(&current, 0o755).is_err() && sftp.metadata(&current).is_err() {
            return Err(CoreError::Ssh(format!(
                "failed to create remote directory '{current}'"
            )));
        }
    }

    Ok(())
}

fn ensure_remote_parent_exists(sftp: &Sftp, remote_path: &str) -> CoreResult<()> {
    if let Some(parent) = remote_parent(remote_path) {
        ensure_remote_directory_exists(sftp, &parent)?;
    }
    Ok(())
}

fn ensure_local_parent_exists(path: &str) -> CoreResult<()> {
    if let Some(parent) = Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            create_dir_all(parent)?;
        }
    }
    Ok(())
}

fn chunk_size_or_default(chunk_size: usize) -> usize {
    chunk_size.max(32 * 1024)
}

const RESUME_HEAD_SAMPLE_BYTES: usize = 4 * 1024;
const RESUME_META_SUFFIX: &str = ".Polarmote.resume.json";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct ResumeFingerprint {
    size: u64,
    head_b64: String,
}

fn read_head_base64<T: Read + Seek>(reader: &mut T) -> CoreResult<String> {
    let original_position = reader.stream_position()?;
    reader.seek(SeekFrom::Start(0))?;
    let mut buffer = vec![0u8; RESUME_HEAD_SAMPLE_BYTES];
    let bytes_read = reader.read(&mut buffer)?;
    buffer.truncate(bytes_read);
    reader.seek(SeekFrom::Start(original_position))?;
    Ok(BASE64_STANDARD.encode(&buffer))
}

fn build_local_fingerprint(local_file: &mut LocalFile, size: u64) -> CoreResult<ResumeFingerprint> {
    Ok(ResumeFingerprint {
        size,
        head_b64: read_head_base64(local_file)?,
    })
}

fn build_remote_fingerprint<T: Read + Seek>(
    remote_file: &mut T,
    size: u64,
) -> CoreResult<ResumeFingerprint> {
    Ok(ResumeFingerprint {
        size,
        head_b64: read_head_base64(remote_file)?,
    })
}

fn remote_resume_meta_path(remote_path: &str) -> String {
    format!(
        "{}{}",
        normalize_remote_path(remote_path),
        RESUME_META_SUFFIX
    )
}

fn local_resume_meta_path(local_path: &str) -> PathBuf {
    PathBuf::from(format!("{local_path}{RESUME_META_SUFFIX}"))
}

fn read_remote_resume_fingerprint(sftp: &Sftp, meta_path: &str) -> Option<ResumeFingerprint> {
    let mut meta_file = sftp.open(meta_path, OpenFlags::READ_ONLY, 0).ok()?;
    let mut bytes = Vec::new();
    meta_file.read_to_end(&mut bytes).ok()?;
    serde_json::from_slice::<ResumeFingerprint>(&bytes).ok()
}

fn write_remote_resume_fingerprint(
    sftp: &Sftp,
    meta_path: &str,
    fingerprint: &ResumeFingerprint,
) -> CoreResult<()> {
    let payload = serde_json::to_vec(fingerprint)?;
    let mut meta_file = sftp.open(
        meta_path,
        OpenFlags::WRITE_ONLY | OpenFlags::CREATE | OpenFlags::TRUNCATE,
        0o644,
    )?;
    meta_file.write_all(&payload)?;
    Ok(())
}

fn read_local_resume_fingerprint(meta_path: &Path) -> Option<ResumeFingerprint> {
    let bytes = fs::read(meta_path).ok()?;
    serde_json::from_slice::<ResumeFingerprint>(&bytes).ok()
}

fn write_local_resume_fingerprint(
    meta_path: &Path,
    fingerprint: &ResumeFingerprint,
) -> CoreResult<()> {
    if let Some(parent) = meta_path.parent() {
        if !parent.as_os_str().is_empty() {
            create_dir_all(parent)?;
        }
    }
    let payload = serde_json::to_vec(fingerprint)?;
    fs::write(meta_path, payload)?;
    Ok(())
}

fn remove_remote_file_if_exists(sftp: &Sftp, path: &str) {
    let _ = sftp.remove_file(path);
}

const PROGRESS_EMIT_MIN_BYTES: u64 = 512 * 1024;
const PROGRESS_EMIT_MIN_INTERVAL: Duration = Duration::from_millis(120);

fn should_emit_progress(
    transferred: u64,
    total: Option<u64>,
    last_emit_bytes: u64,
    last_emit_at: Instant,
) -> bool {
    if total.is_some_and(|value| transferred >= value) {
        return true;
    }
    if transferred.saturating_sub(last_emit_bytes) >= PROGRESS_EMIT_MIN_BYTES {
        return true;
    }
    last_emit_at.elapsed() >= PROGRESS_EMIT_MIN_INTERVAL
}

pub fn upload_file_with_connection<F>(
    connection: &SftpConnection,
    local_path: &str,
    remote_path: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    mut on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    ensure_not_cancelled(cancelled)?;

    let mut local_file = LocalFile::open(local_path)?;
    let total = local_file.metadata()?.len();
    let local_fingerprint = build_local_fingerprint(&mut local_file, total)?;
    let remote_path = normalize_remote_path(remote_path);
    ensure_remote_parent_exists(connection.sftp(), &remote_path)?;
    let resume_meta_path = remote_resume_meta_path(&remote_path);
    let mut transferred: u64 = 0;

    let mut remote_flags = OpenFlags::WRITE_ONLY | OpenFlags::CREATE | OpenFlags::TRUNCATE;
    if connection.resume_enabled() {
        if let Ok(remote_meta) = connection.sftp().metadata(&remote_path) {
            if let Some(remote_size) = remote_meta.len() {
                let remote_fingerprint =
                    read_remote_resume_fingerprint(connection.sftp(), &resume_meta_path);
                if remote_size < total
                    && remote_fingerprint
                        .as_ref()
                        .is_some_and(|fingerprint| fingerprint == &local_fingerprint)
                {
                    remote_flags = OpenFlags::WRITE_ONLY | OpenFlags::CREATE;
                    transferred = remote_size;
                }
            }
        }
    }

    let mut remote_file = connection.sftp().open(&remote_path, remote_flags, 0o644)?;
    if connection.resume_enabled() && transferred == 0 {
        write_remote_resume_fingerprint(connection.sftp(), &resume_meta_path, &local_fingerprint)?;
    }
    if transferred > 0 {
        remote_file.seek(SeekFrom::Start(transferred))?;
        local_file.seek(SeekFrom::Start(transferred))?;
    }

    on_progress(transferred, Some(total))?;

    let mut buffer = vec![0u8; chunk_size_or_default(chunk_size)];
    let mut last_emit_bytes = transferred;
    let mut last_emit_at = Instant::now();

    loop {
        ensure_not_cancelled(cancelled)?;
        let bytes_read = local_file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }

        remote_file.write_all(&buffer[..bytes_read])?;
        transferred += bytes_read as u64;
        if should_emit_progress(transferred, Some(total), last_emit_bytes, last_emit_at) {
            on_progress(transferred, Some(total))?;
            last_emit_bytes = transferred;
            last_emit_at = Instant::now();
        }
    }

    if transferred != last_emit_bytes || transferred == total {
        on_progress(total, Some(total))?;
    }
    remove_remote_file_if_exists(connection.sftp(), &resume_meta_path);

    Ok(TaskExecutionOutput {
        transferred_bytes: transferred,
        total_bytes: Some(total),
        value_u64: None,
    })
}

pub fn download_file_with_connection<F>(
    connection: &SftpConnection,
    remote_path: &str,
    local_path: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    mut on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    ensure_not_cancelled(cancelled)?;

    let remote_path = normalize_remote_path(remote_path);
    let total_hint = connection.sftp().metadata(&remote_path)?.len();
    ensure_local_parent_exists(local_path)?;
    let resume_meta_path = local_resume_meta_path(local_path);

    let mut remote_file = connection
        .sftp()
        .open(&remote_path, OpenFlags::READ_ONLY, 0)?;
    let remote_fingerprint = if let Some(total) = total_hint {
        Some(build_remote_fingerprint(&mut remote_file, total)?)
    } else {
        None
    };
    remote_file.seek(SeekFrom::Start(0))?;
    let mut transferred: u64 = 0;
    let mut local_file = if connection.resume_enabled() {
        match (
            std::fs::metadata(local_path),
            read_local_resume_fingerprint(&resume_meta_path),
            remote_fingerprint.as_ref(),
        ) {
            (Ok(local_meta), Some(saved), Some(remote))
                if saved == *remote && local_meta.len() < remote.size =>
            {
                transferred = local_meta.len();
                remote_file.seek(SeekFrom::Start(transferred))?;
                LocalFile::options().append(true).open(local_path)?
            }
            _ => LocalFile::create(local_path)?,
        }
    } else {
        LocalFile::create(local_path)?
    };
    if connection.resume_enabled() && transferred == 0 {
        if let Some(remote) = remote_fingerprint.as_ref() {
            write_local_resume_fingerprint(&resume_meta_path, remote)?;
        }
    }

    on_progress(transferred, total_hint)?;

    let mut buffer = vec![0u8; chunk_size_or_default(chunk_size)];
    let mut last_emit_bytes = transferred;
    let mut last_emit_at = Instant::now();

    loop {
        ensure_not_cancelled(cancelled)?;
        let bytes_read = remote_file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }

        local_file.write_all(&buffer[..bytes_read])?;
        transferred += bytes_read as u64;
        if should_emit_progress(transferred, total_hint, last_emit_bytes, last_emit_at) {
            on_progress(transferred, total_hint)?;
            last_emit_bytes = transferred;
            last_emit_at = Instant::now();
        }
    }

    local_file.flush()?;
    let output_total = total_hint.or(Some(transferred));
    if transferred != last_emit_bytes {
        on_progress(transferred, output_total)?;
    }
    let _ = fs::remove_file(&resume_meta_path);

    Ok(TaskExecutionOutput {
        transferred_bytes: transferred,
        total_bytes: output_total,
        value_u64: None,
    })
}

pub fn ensure_parent_dirs_with_connection(
    connection: &SftpConnection,
    remote_path: &str,
    cancelled: &AtomicBool,
) -> CoreResult<TaskExecutionOutput> {
    ensure_not_cancelled(cancelled)?;
    let remote_path = normalize_remote_path(remote_path);
    ensure_remote_parent_exists(connection.sftp(), &remote_path)?;
    Ok(TaskExecutionOutput {
        transferred_bytes: 0,
        total_bytes: None,
        value_u64: None,
    })
}

pub fn probe_remote_file_size_with_connection(
    connection: &SftpConnection,
    remote_path: &str,
    cancelled: &AtomicBool,
) -> CoreResult<TaskExecutionOutput> {
    ensure_not_cancelled(cancelled)?;
    let remote_path = normalize_remote_path(remote_path);
    let size = connection.sftp().metadata(&remote_path)?.len().unwrap_or(0);
    Ok(TaskExecutionOutput {
        transferred_bytes: size,
        total_bytes: Some(size),
        value_u64: Some(size),
    })
}

enum LocalBatchEntry {
    Dir {
        relative: String,
    },
    File {
        local_path: PathBuf,
        relative: String,
        size: u64,
    },
}

fn collect_local_batch_entries(
    local_path: &Path,
    relative_root: String,
    entries: &mut Vec<LocalBatchEntry>,
    total_size: &mut u64,
    cancelled: &AtomicBool,
) -> CoreResult<()> {
    ensure_not_cancelled(cancelled)?;
    let metadata = fs::metadata(local_path)?;

    if metadata.is_dir() {
        entries.push(LocalBatchEntry::Dir {
            relative: relative_root.clone(),
        });

        let mut children: Vec<PathBuf> = fs::read_dir(local_path)?
            .filter_map(|entry| entry.ok().map(|item| item.path()))
            .collect();
        children.sort();

        for child in children {
            let child_name = child
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .ok_or_else(|| {
                    CoreError::Internal(format!("invalid local path '{}'", child.to_string_lossy()))
                })?;
            let child_relative = format!("{}/{}", relative_root, child_name.replace('\\', "/"));
            collect_local_batch_entries(&child, child_relative, entries, total_size, cancelled)?;
        }
    } else {
        let size = metadata.len();
        entries.push(LocalBatchEntry::File {
            local_path: local_path.to_path_buf(),
            relative: relative_root,
            size,
        });
        *total_size += size;
    }

    Ok(())
}

pub fn upload_batch_with_connection<F>(
    connection: &SftpConnection,
    local_paths: &[String],
    target_dir: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    mut on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let target_dir = normalize_remote_path(target_dir);

    let mut entries = Vec::new();
    let mut total_size = 0u64;

    for local_path in local_paths {
        ensure_not_cancelled(cancelled)?;
        let path = Path::new(local_path);
        let relative_root = path
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .ok_or_else(|| CoreError::Internal(format!("invalid local path '{local_path}'")))?;
        collect_local_batch_entries(
            path,
            relative_root,
            &mut entries,
            &mut total_size,
            cancelled,
        )?;
    }

    on_progress(0, Some(total_size))?;

    let mut transferred_total = 0u64;
    for entry in entries {
        ensure_not_cancelled(cancelled)?;
        match entry {
            LocalBatchEntry::Dir { relative } => {
                let remote_dir = join_remote_path(&target_dir, &relative);
                ensure_remote_directory_exists(connection.sftp(), &remote_dir)?;
            }
            LocalBatchEntry::File {
                local_path,
                relative,
                size: _size,
            } => {
                let remote_path = join_remote_path(&target_dir, &relative);
                let local_path = local_path.to_string_lossy().to_string();
                let output = upload_file_with_connection(
                    connection,
                    &local_path,
                    &remote_path,
                    chunk_size,
                    cancelled,
                    |transferred, _| on_progress(transferred_total + transferred, Some(total_size)),
                )?;
                transferred_total += output.transferred_bytes;
            }
        }
    }

    on_progress(transferred_total, Some(total_size))?;

    Ok(TaskExecutionOutput {
        transferred_bytes: transferred_total,
        total_bytes: Some(total_size),
        value_u64: None,
    })
}

pub fn upload_batch<F>(
    config: &SessionConfig,
    local_paths: &[String],
    target_dir: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let connection = SftpConnection::connect(config)?;
    upload_batch_with_connection(
        &connection,
        local_paths,
        target_dir,
        chunk_size,
        cancelled,
        on_progress,
    )
}

enum RemoteBatchEntry {
    Dir {
        relative: String,
    },
    File {
        remote_path: String,
        relative: String,
        size: u64,
    },
}

fn is_directory(file_type: Option<FileType>) -> bool {
    matches!(file_type, Some(FileType::Directory))
}

fn collect_remote_batch_entries(
    connection: &SftpConnection,
    remote_path: &str,
    relative_root: String,
    entries: &mut Vec<RemoteBatchEntry>,
    total_size: &mut u64,
    cancelled: &AtomicBool,
) -> CoreResult<()> {
    ensure_not_cancelled(cancelled)?;

    let remote_path = normalize_remote_path(remote_path);
    let metadata = connection.sftp().metadata(&remote_path)?;

    if is_directory(metadata.file_type()) {
        entries.push(RemoteBatchEntry::Dir {
            relative: relative_root.clone(),
        });

        let mut children = connection.sftp().read_dir(&remote_path)?;
        children.sort_by(|a, b| a.name().cmp(&b.name()));

        for child in children {
            ensure_not_cancelled(cancelled)?;

            let Some(name) = child.name().map(str::to_string) else {
                continue;
            };
            if name == "." || name == ".." {
                continue;
            }

            let child_remote_path = join_remote_path(&remote_path, &name);
            let child_relative = format!("{}/{}", relative_root, name);
            if is_directory(child.file_type()) {
                collect_remote_batch_entries(
                    connection,
                    &child_remote_path,
                    child_relative,
                    entries,
                    total_size,
                    cancelled,
                )?;
            } else {
                let size = child
                    .len()
                    .or_else(|| connection.sftp().metadata(&child_remote_path).ok()?.len())
                    .unwrap_or(0);
                entries.push(RemoteBatchEntry::File {
                    remote_path: child_remote_path,
                    relative: child_relative,
                    size,
                });
                *total_size += size;
            }
        }
    } else {
        let size = metadata.len().unwrap_or(0);
        entries.push(RemoteBatchEntry::File {
            remote_path,
            relative: relative_root,
            size,
        });
        *total_size += size;
    }

    Ok(())
}

fn relative_local_path(target_dir: &str, relative_path: &str) -> PathBuf {
    let mut result = PathBuf::from(target_dir);
    for segment in relative_path.split('/').filter(|item| !item.is_empty()) {
        result.push(segment);
    }
    result
}

pub fn download_batch_with_connection<F>(
    connection: &SftpConnection,
    remote_paths: &[String],
    target_dir: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    mut on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let mut entries = Vec::new();
    let mut total_size = 0u64;
    for remote_path in remote_paths {
        ensure_not_cancelled(cancelled)?;
        let root_name = remote_basename(remote_path).ok_or_else(|| {
            CoreError::Internal(format!(
                "invalid remote path '{remote_path}' for batch download"
            ))
        })?;
        collect_remote_batch_entries(
            &connection,
            remote_path,
            root_name,
            &mut entries,
            &mut total_size,
            cancelled,
        )?;
    }

    on_progress(0, Some(total_size))?;

    let mut transferred_total = 0u64;
    for entry in entries {
        ensure_not_cancelled(cancelled)?;
        match entry {
            RemoteBatchEntry::Dir { relative } => {
                let local_dir = relative_local_path(target_dir, &relative);
                create_dir_all(local_dir)?;
            }
            RemoteBatchEntry::File {
                remote_path,
                relative,
                size: _size,
            } => {
                let local_path = relative_local_path(target_dir, &relative);
                if let Some(parent) = local_path.parent() {
                    create_dir_all(parent)?;
                }
                let local_path_text = local_path.to_string_lossy().to_string();
                let output = download_file_with_connection(
                    connection,
                    &remote_path,
                    &local_path_text,
                    chunk_size,
                    cancelled,
                    |transferred, _| on_progress(transferred_total + transferred, Some(total_size)),
                )?;
                transferred_total += output.transferred_bytes;
            }
        }
    }

    on_progress(transferred_total, Some(total_size))?;

    Ok(TaskExecutionOutput {
        transferred_bytes: transferred_total,
        total_bytes: Some(total_size),
        value_u64: None,
    })
}

pub fn download_batch<F>(
    config: &SessionConfig,
    remote_paths: &[String],
    target_dir: &str,
    chunk_size: usize,
    cancelled: &AtomicBool,
    on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let connection = SftpConnection::connect(config)?;
    download_batch_with_connection(
        &connection,
        remote_paths,
        target_dir,
        chunk_size,
        cancelled,
        on_progress,
    )
}
