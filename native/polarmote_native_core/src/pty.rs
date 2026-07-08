use crate::error::{CoreError, CoreResult};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Default)]
pub struct PtyPollPayload {
    pub chunks: Vec<String>,
    pub closed: bool,
    pub exit_code: Option<i32>,
    pub error: Option<String>,
}

#[cfg(target_os = "ios")]
mod imp {
    use super::*;

    pub fn is_supported() -> bool {
        false
    }

    pub fn spawn(_config_json: &str) -> CoreResult<u64> {
        Err(CoreError::Internal(
            "local pty is not supported on ios".to_owned(),
        ))
    }

    pub fn write(_session_id: u64, _data: &[u8]) -> CoreResult<()> {
        Err(CoreError::Internal(
            "local pty is not supported on ios".to_owned(),
        ))
    }

    pub fn resize(_session_id: u64, _cols: u16, _rows: u16) -> CoreResult<()> {
        Err(CoreError::Internal(
            "local pty is not supported on ios".to_owned(),
        ))
    }

    pub fn poll(_session_id: u64) -> CoreResult<PtyPollPayload> {
        Ok(PtyPollPayload {
            chunks: Vec::new(),
            closed: true,
            exit_code: None,
            error: Some("local pty is not supported on ios".to_owned()),
        })
    }

    pub fn close(_session_id: u64) -> CoreResult<()> {
        Ok(())
    }
}

#[cfg(not(target_os = "ios"))]
mod imp {
    use super::*;
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    use base64::Engine;
    use once_cell::sync::Lazy;
    use portable_pty::{native_pty_system, ChildKiller, CommandBuilder, MasterPty, PtySize};
    use std::collections::{HashMap, VecDeque};
    use std::io::{ErrorKind, Read, Write};
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::sync::{Arc, Mutex, MutexGuard};

    const DEFAULT_COLS: u16 = 160; // 增加默认列数以匹配 OpenCode 建议
    const DEFAULT_ROWS: u16 = 50;  // 增加默认行数
    const READ_BUFFER_SIZE: usize = 64 * 1024; // 增加到 64KB 以支持 TUI 程序

    #[derive(Debug, Clone, Deserialize, Default)]
    struct PtySpawnConfig {
        #[serde(default)]
        program: Option<String>,
        #[serde(default)]
        args: Vec<String>,
        #[serde(default)]
        cwd: Option<String>,
        #[serde(default)]
        env: HashMap<String, String>,
        #[serde(default)]
        cols: Option<u16>,
        #[serde(default)]
        rows: Option<u16>,
    }

    struct LocalPtySession {
        master: Mutex<Box<dyn MasterPty + Send>>,
        writer: Mutex<Box<dyn Write + Send>>,
        killer: Mutex<Option<Box<dyn ChildKiller + Send + Sync>>>,
        output_chunks: Arc<Mutex<VecDeque<String>>>,
        closed: Arc<AtomicBool>,
        exit_code: Arc<Mutex<Option<i32>>>,
        error: Arc<Mutex<Option<String>>>,
    }

    impl LocalPtySession {
        fn spawn(id: u64, config: PtySpawnConfig) -> CoreResult<Self> {
            let program = resolve_program(&config);
            let args = resolve_args(&config);
            let rows = config.rows.unwrap_or(DEFAULT_ROWS).max(1);
            let cols = config.cols.unwrap_or(DEFAULT_COLS).max(1);
            let pty_size = PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            };

            let pty_system = native_pty_system();
            let pair = pty_system
                .openpty(pty_size)
                .map_err(|err| CoreError::Internal(format!("open pty failed: {err}")))?;

            let mut cmd = CommandBuilder::new(program);
            for arg in args {
                cmd.arg(arg);
            }
            if let Some(cwd) = config
                .cwd
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                cmd.cwd(cwd);
            }
            for (key, value) in config.env {
                cmd.env(key, value);
            }

            let mut child = pair
                .slave
                .spawn_command(cmd)
                .map_err(|err| CoreError::Internal(format!("spawn pty child failed: {err}")))?;
            let killer = child.clone_killer();
            let mut reader = pair
                .master
                .try_clone_reader()
                .map_err(|err| CoreError::Internal(format!("clone pty reader failed: {err}")))?;
            let writer = pair
                .master
                .take_writer()
                .map_err(|err| CoreError::Internal(format!("take pty writer failed: {err}")))?;

            let output_chunks = Arc::new(Mutex::new(VecDeque::new()));
            let closed = Arc::new(AtomicBool::new(false));
            let exit_code = Arc::new(Mutex::new(None));
            let error = Arc::new(Mutex::new(None));

            let output_for_reader = Arc::clone(&output_chunks);
            let closed_for_reader = Arc::clone(&closed);
            let error_for_reader = Arc::clone(&error);
            std::thread::Builder::new()
                .name(format!("Polarmote-pty-read-{id}"))
                .spawn(move || {
                    let mut buffer = [0u8; READ_BUFFER_SIZE];
                    loop {
                        match reader.read(&mut buffer) {
                            Ok(0) => break,
                            Ok(len) => {
                                let encoded = BASE64_STANDARD.encode(&buffer[..len]);
                                let mut queue = lock_unpoison(&output_for_reader);
                                queue.push_back(encoded);
                            }
                            Err(err) => {
                                if err.kind() != ErrorKind::Interrupted {
                                    set_error_once(
                                        &error_for_reader,
                                        format!("pty read failed: {err}"),
                                    );
                                    break;
                                }
                            }
                        }
                    }
                    closed_for_reader.store(true, Ordering::SeqCst);
                })
                .map_err(|err| CoreError::Internal(format!("spawn read thread failed: {err}")))?;

            let closed_for_wait = Arc::clone(&closed);
            let exit_for_wait = Arc::clone(&exit_code);
            let error_for_wait = Arc::clone(&error);
            std::thread::Builder::new()
                .name(format!("Polarmote-pty-wait-{id}"))
                .spawn(move || {
                    match child.wait() {
                        Ok(status) => {
                            let code_u32 = status.exit_code();
                            let code_i32 = if code_u32 > i32::MAX as u32 {
                                i32::MAX
                            } else {
                                code_u32 as i32
                            };
                            *lock_unpoison(&exit_for_wait) = Some(code_i32);
                            if let Some(signal) = status.signal() {
                                set_error_once(
                                    &error_for_wait,
                                    format!("pty process terminated by {signal}"),
                                );
                            }
                        }
                        Err(err) => {
                            set_error_once(
                                &error_for_wait,
                                format!("wait pty child failed: {err}"),
                            );
                        }
                    }
                    closed_for_wait.store(true, Ordering::SeqCst);
                })
                .map_err(|err| CoreError::Internal(format!("spawn wait thread failed: {err}")))?;

            Ok(Self {
                master: Mutex::new(pair.master),
                writer: Mutex::new(writer),
                killer: Mutex::new(Some(killer)),
                output_chunks,
                closed,
                exit_code,
                error,
            })
        }

        fn write(&self, data: &[u8]) -> CoreResult<()> {
            if data.is_empty() {
                return Ok(());
            }
            let mut writer = lock_unpoison(&self.writer);
            writer
                .write_all(data)
                .map_err(|err| CoreError::Io(err.to_string()))?;
            writer
                .flush()
                .map_err(|err| CoreError::Io(err.to_string()))?;
            Ok(())
        }

        fn resize(&self, cols: u16, rows: u16) -> CoreResult<()> {
            let size = PtySize {
                rows: rows.max(1),
                cols: cols.max(1),
                pixel_width: 0,
                pixel_height: 0,
            };
            let master = lock_unpoison(&self.master);
            master
                .resize(size)
                .map_err(|err| CoreError::Internal(format!("resize pty failed: {err}")))
        }

        fn poll(&self) -> PtyPollPayload {
            let mut chunks = Vec::new();
            {
                let mut queue = lock_unpoison(&self.output_chunks);
                while let Some(chunk) = queue.pop_front() {
                    chunks.push(chunk);
                }
            }
            PtyPollPayload {
                chunks,
                closed: self.closed.load(Ordering::SeqCst),
                exit_code: *lock_unpoison(&self.exit_code),
                error: lock_unpoison(&self.error).clone(),
            }
        }

        fn close(&self) {
            let killer = lock_unpoison(&self.killer).take();
            if let Some(mut killer) = killer {
                let _ = std::thread::Builder::new()
                    .name("Polarmote-pty-kill".to_owned())
                    .spawn(move || {
                        let _ = killer.kill();
                    });
            }
            self.closed.store(true, Ordering::SeqCst);
        }
    }

    pub struct NativePtyCore {
        sessions: Mutex<HashMap<u64, Arc<LocalPtySession>>>,
        next_session_id: AtomicU64,
    }

    impl NativePtyCore {
        fn new() -> Self {
            Self {
                sessions: Mutex::new(HashMap::new()),
                next_session_id: AtomicU64::new(1),
            }
        }

        fn global() -> &'static Self {
            static INSTANCE: Lazy<NativePtyCore> = Lazy::new(NativePtyCore::new);
            &INSTANCE
        }

        fn spawn(&self, config_json: &str) -> CoreResult<u64> {
            let config: PtySpawnConfig = serde_json::from_str(config_json)?;
            let id = self.next_session_id.fetch_add(1, Ordering::Relaxed);
            let session = Arc::new(LocalPtySession::spawn(id, config)?);
            lock_unpoison(&self.sessions).insert(id, session);
            Ok(id)
        }

        fn session(&self, session_id: u64) -> CoreResult<Arc<LocalPtySession>> {
            lock_unpoison(&self.sessions)
                .get(&session_id)
                .cloned()
                .ok_or(CoreError::SessionNotFound(session_id))
        }

        fn write(&self, session_id: u64, data: &[u8]) -> CoreResult<()> {
            self.session(session_id)?.write(data)
        }

        fn resize(&self, session_id: u64, cols: u16, rows: u16) -> CoreResult<()> {
            self.session(session_id)?.resize(cols, rows)
        }

        fn poll(&self, session_id: u64) -> CoreResult<PtyPollPayload> {
            Ok(self.session(session_id)?.poll())
        }

        fn close(&self, session_id: u64) -> CoreResult<()> {
            let removed = lock_unpoison(&self.sessions).remove(&session_id);
            if let Some(session) = removed {
                let _ = std::thread::Builder::new()
                    .name(format!("Polarmote-pty-close-{session_id}"))
                    .spawn(move || {
                        session.close();
                    });
                return Ok(());
            }
            Err(CoreError::SessionNotFound(session_id))
        }
    }

    fn resolve_program(config: &PtySpawnConfig) -> String {
        if let Some(program) = config
            .program
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return program.to_owned();
        }
        default_program()
    }

    fn resolve_args(config: &PtySpawnConfig) -> Vec<String> {
        let provided = config
            .args
            .iter()
            .map(|arg| arg.trim())
            .filter(|arg| !arg.is_empty())
            .map(ToOwned::to_owned)
            .collect::<Vec<_>>();
        if !provided.is_empty() {
            return provided;
        }
        default_args()
    }

    fn default_program() -> String {
        #[cfg(windows)]
        {
            return "cmd.exe".to_owned();
        }

        #[cfg(target_os = "android")]
        {
            return "/system/bin/sh".to_owned();
        }

        #[cfg(all(unix, not(target_os = "android")))]
        {
            if let Ok(shell) = std::env::var("SHELL") {
                let trimmed = shell.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_owned();
                }
            }
            return "/bin/sh".to_owned();
        }

        #[allow(unreachable_code)]
        "sh".to_owned()
    }

    fn default_args() -> Vec<String> {
        #[cfg(windows)]
        {
            return Vec::new();
        }

        #[cfg(not(windows))]
        {
            return vec!["-i".to_owned()];
        }
    }

    fn set_error_once(target: &Mutex<Option<String>>, message: String) {
        let mut slot = lock_unpoison(target);
        if slot.is_none() {
            *slot = Some(message);
        }
    }

    fn lock_unpoison<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
        match mutex.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    pub fn is_supported() -> bool {
        true
    }

    pub fn spawn(config_json: &str) -> CoreResult<u64> {
        NativePtyCore::global().spawn(config_json)
    }

    pub fn write(session_id: u64, data: &[u8]) -> CoreResult<()> {
        NativePtyCore::global().write(session_id, data)
    }

    pub fn resize(session_id: u64, cols: u16, rows: u16) -> CoreResult<()> {
        NativePtyCore::global().resize(session_id, cols, rows)
    }

    pub fn poll(session_id: u64) -> CoreResult<PtyPollPayload> {
        NativePtyCore::global().poll(session_id)
    }

    pub fn close(session_id: u64) -> CoreResult<()> {
        NativePtyCore::global().close(session_id)
    }
}

pub fn is_supported() -> bool {
    imp::is_supported()
}

pub fn spawn(config_json: &str) -> CoreResult<u64> {
    imp::spawn(config_json)
}

pub fn write(session_id: u64, data: &[u8]) -> CoreResult<()> {
    imp::write(session_id, data)
}

pub fn resize(session_id: u64, cols: u16, rows: u16) -> CoreResult<()> {
    imp::resize(session_id, cols, rows)
}

pub fn poll(session_id: u64) -> CoreResult<PtyPollPayload> {
    imp::poll(session_id)
}

pub fn close(session_id: u64) -> CoreResult<()> {
    imp::close(session_id)
}
