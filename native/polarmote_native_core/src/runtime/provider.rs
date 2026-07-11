use crate::error::{CoreError, CoreResult};
use crate::models::{SessionConfig, TaskExecutionOutput};
use crate::transport::sftp::{
    download_batch_with_connection, download_file_with_connection,
    probe_remote_file_size_with_connection, upload_batch_with_connection,
    upload_file_with_connection, SftpConnection,
};
use libssh_rs::FileType;
use std::collections::VecDeque;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub trait TransportProvider: Send {
    fn connect(&mut self, config: &SessionConfig) -> CoreResult<()>;
    fn disconnect(&mut self);
    fn is_connected(&self) -> bool;
    fn probe(&mut self) -> CoreResult<()> { Ok(()) }

    fn upload(
        &self,
        local_path: &str,
        remote_path: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput>;

    fn download(
        &self,
        remote_path: &str,
        local_path: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput>;

    fn upload_batch(
        &self,
        config: &SessionConfig,
        local_paths: &[String],
        target_dir: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput>;

    fn download_batch(
        &self,
        config: &SessionConfig,
        remote_paths: &[String],
        target_dir: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput>;

    fn mkdir_remote(&self, path: &str, mode: u32) -> CoreResult<()>;
    fn stat_remote(&self, path: &str) -> CoreResult<Option<FileMetadata>>;
    fn list_remote(&self, path: &str) -> CoreResult<Vec<FileMetadata>>;
    fn remove_remote(&self, path: &str) -> CoreResult<()>;
    fn probe_remote_file_size(
        &self,
        path: &str,
        cancelled: &AtomicBool,
    ) -> CoreResult<TaskExecutionOutput>;
}

#[derive(Debug, Clone)]
pub struct FileMetadata {
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
    #[allow(dead_code)]
    pub permissions: Option<u32>,
}

#[derive(Default)]
pub struct SftpProvider {
    config: Option<SessionConfig>,
    connection: Option<SftpConnection>,
}

impl SftpProvider {
    fn connection_ref(&self) -> CoreResult<&SftpConnection> {
        self.connection
            .as_ref()
            .ok_or_else(|| CoreError::Ssh("sftp provider is not connected".to_string()))
    }

    fn normalize_remote_path(path: &str) -> String {
        path.replace('\\', "/")
    }

    fn is_dir(file_type: Option<FileType>) -> bool {
        matches!(file_type, Some(FileType::Directory))
    }
}

impl TransportProvider for SftpProvider {
    fn connect(&mut self, config: &SessionConfig) -> CoreResult<()> {
        self.connection = Some(SftpConnection::connect(config)?);
        self.config = Some(config.clone());
        Ok(())
    }

    fn disconnect(&mut self) {
        self.connection = None;
    }

    fn is_connected(&self) -> bool {
        self.connection.is_some()
    }

    fn probe(&mut self) -> CoreResult<()> {
        let conn = self.connection_ref()?;
        match conn.sftp().metadata("/") {
            Ok(_) => Ok(()),
            Err(e) => Err(e.into()),
        }
    }

    fn upload(
        &self,
        local_path: &str,
        remote_path: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput> {
        let connection = self.connection_ref()?;
        upload_file_with_connection(
            connection,
            local_path,
            &Self::normalize_remote_path(remote_path),
            chunk_size,
            cancelled,
            on_progress,
        )
    }

    fn download(
        &self,
        remote_path: &str,
        local_path: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput> {
        let connection = self.connection_ref()?;
        download_file_with_connection(
            connection,
            &Self::normalize_remote_path(remote_path),
            local_path,
            chunk_size,
            cancelled,
            on_progress,
        )
    }

    fn upload_batch(
        &self,
        _config: &SessionConfig,
        local_paths: &[String],
        target_dir: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput> {
        let connection = self.connection_ref()?;
        upload_batch_with_connection(
            connection,
            local_paths,
            &Self::normalize_remote_path(target_dir),
            chunk_size,
            cancelled,
            on_progress,
        )
    }

    fn download_batch(
        &self,
        _config: &SessionConfig,
        remote_paths: &[String],
        target_dir: &str,
        chunk_size: usize,
        cancelled: &AtomicBool,
        on_progress: &mut dyn FnMut(u64, Option<u64>) -> CoreResult<()>,
    ) -> CoreResult<TaskExecutionOutput> {
        let connection = self.connection_ref()?;
        let normalized: Vec<String> = remote_paths
            .iter()
            .map(|path| Self::normalize_remote_path(path))
            .collect();
        download_batch_with_connection(
            connection,
            &normalized,
            target_dir,
            chunk_size,
            cancelled,
            on_progress,
        )
    }

    fn mkdir_remote(&self, path: &str, mode: u32) -> CoreResult<()> {
        let connection = self.connection_ref()?;
        let _ = connection
            .sftp()
            .create_dir(&Self::normalize_remote_path(path), mode)
            .ok();
        Ok(())
    }

    fn stat_remote(&self, path: &str) -> CoreResult<Option<FileMetadata>> {
        let connection = self.connection_ref()?;
        match connection
            .sftp()
            .metadata(&Self::normalize_remote_path(path))
        {
            Ok(meta) => Ok(Some(FileMetadata {
                path: path.to_string(),
                size: meta.len().unwrap_or(0),
                is_dir: Self::is_dir(meta.file_type()),
                permissions: meta.permissions(),
            })),
            Err(_) => Ok(None),
        }
    }

    fn list_remote(&self, path: &str) -> CoreResult<Vec<FileMetadata>> {
        let connection = self.connection_ref()?;
        let normalized = Self::normalize_remote_path(path);
        let entries = connection.sftp().read_dir(&normalized)?;

        let mut output = Vec::with_capacity(entries.len());
        for entry in entries {
            let Some(name) = entry.name() else {
                continue;
            };
            if name == "." || name == ".." {
                continue;
            }
            let joined = if normalized == "/" {
                format!("/{name}")
            } else {
                format!("{}/{}", normalized.trim_end_matches('/'), name)
            };
            output.push(FileMetadata {
                path: joined,
                size: entry.len().unwrap_or(0),
                is_dir: Self::is_dir(entry.file_type()),
                permissions: entry.permissions(),
            });
        }
        Ok(output)
    }

    fn remove_remote(&self, path: &str) -> CoreResult<()> {
        let connection = self.connection_ref()?;
        let normalized = Self::normalize_remote_path(path);

        let meta = connection.sftp().metadata(&normalized)?;
        if Self::is_dir(meta.file_type()) {
            // Depth-first remove to support non-empty directory deletion.
            let mut queue = VecDeque::new();
            queue.push_back(normalized.clone());
            let mut dirs = Vec::new();

            while let Some(current) = queue.pop_front() {
                dirs.push(current.clone());
                let children = connection.sftp().read_dir(&current)?;
                for child in children {
                    let Some(name) = child.name() else {
                        continue;
                    };
                    if name == "." || name == ".." {
                        continue;
                    }
                    let full = format!("{}/{}", current.trim_end_matches('/'), name);
                    if Self::is_dir(child.file_type()) {
                        queue.push_back(full);
                    } else {
                        let _ = connection.sftp().remove_file(&full);
                    }
                }
            }

            for dir in dirs.into_iter().rev() {
                let _ = connection.sftp().remove_dir(&dir);
            }
            Ok(())
        } else {
            connection.sftp().remove_file(&normalized)?;
            Ok(())
        }
    }

    fn probe_remote_file_size(
        &self,
        path: &str,
        cancelled: &AtomicBool,
    ) -> CoreResult<TaskExecutionOutput> {
        let connection = self.connection_ref()?;
        probe_remote_file_size_with_connection(connection, path, cancelled)
    }
}

pub struct ConnectionPool<T: TransportProvider + Default + 'static> {
    config: SessionConfig,
    max_size: usize,
    idle_timeout: Duration,
    idle: Arc<Mutex<Vec<PooledConnection<T>>>>,
}

struct PooledConnection<T: TransportProvider + Default + 'static> {
    provider: T,
    last_used: Instant,
}

impl<T: TransportProvider + Default + 'static> ConnectionPool<T> {
    pub fn new(config: SessionConfig, max_size: usize, idle_timeout: Duration) -> Self {
        Self {
            config,
            max_size: max_size.max(1),
            idle_timeout,
            idle: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn acquire(&self) -> CoreResult<PooledConnectionGuard<T>> {
        let mut idle = lock_unpoison(&self.idle);

        while let Some(mut pooled) = idle.pop() {
            if pooled.last_used.elapsed() > self.idle_timeout {
                pooled.provider.disconnect();
                continue;
            }
            if !pooled.provider.is_connected() {
                continue;
            }
            if pooled.provider.probe().is_err() {
                pooled.provider.disconnect();
                continue;
            }
            return Ok(PooledConnectionGuard {
                pooled: Some(pooled),
                idle: Arc::clone(&self.idle),
                max_size: self.max_size,
            });
        }

        drop(idle);
        let mut provider = T::default();
        provider.connect(&self.config)?;

        Ok(PooledConnectionGuard {
            pooled: Some(PooledConnection {
                provider,
                last_used: Instant::now(),
            }),
            idle: Arc::clone(&self.idle),
            max_size: self.max_size,
        })
    }

    #[allow(dead_code)]
    pub fn clear(&self) {
        let mut idle = lock_unpoison(&self.idle);
        for pooled in idle.iter_mut() {
            pooled.provider.disconnect();
        }
        idle.clear();
    }
}

pub struct PooledConnectionGuard<T: TransportProvider + Default + 'static> {
    pooled: Option<PooledConnection<T>>,
    idle: Arc<Mutex<Vec<PooledConnection<T>>>>,
    max_size: usize,
}

impl<T: TransportProvider + Default + 'static> PooledConnectionGuard<T> {
    #[allow(dead_code)]
    pub fn provider(&self) -> &T {
        &self
            .pooled
            .as_ref()
            .expect("pooled connection should exist")
            .provider
    }

    pub fn provider_mut(&mut self) -> &mut T {
        &mut self
            .pooled
            .as_mut()
            .expect("pooled connection should exist")
            .provider
    }
}

impl<T: TransportProvider + Default + 'static> Drop for PooledConnectionGuard<T> {
    fn drop(&mut self) {
        let Some(mut pooled) = self.pooled.take() else {
            return;
        };

        if !pooled.provider.is_connected() {
            return;
        }

        pooled.last_used = Instant::now();
        let mut idle = lock_unpoison(&self.idle);
        if idle.len() >= self.max_size {
            pooled.provider.disconnect();
            return;
        }
        idle.push(pooled);
    }
}

fn lock_unpoison<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}
