use serde::{Deserialize, Serialize};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Deserialize)]
pub struct SessionConfig {
    pub host: String,
    pub port: Option<u16>,
    pub username: String,
    pub password: Option<String>,
    pub private_key_path: Option<String>,
    pub private_key_passphrase: Option<String>,
    pub connect_timeout_ms: Option<u64>,
    pub io_timeout_ms: Option<u64>,
    pub max_concurrency: Option<usize>,
    pub default_chunk_size: Option<usize>,
    pub enable_resume: Option<bool>,
}

impl SessionConfig {
    pub fn port_or_default(&self) -> u16 {
        self.port.unwrap_or(22)
    }

    pub fn connect_timeout(&self) -> Duration {
        Duration::from_millis(self.connect_timeout_ms.unwrap_or(8000).max(500))
    }

    pub fn io_timeout(&self) -> Duration {
        Duration::from_millis(self.io_timeout_ms.unwrap_or(15000).max(500))
    }

    pub fn max_concurrency(&self) -> usize {
        self.max_concurrency.unwrap_or(4).clamp(1, 16)
    }

    pub fn default_chunk_size(&self) -> usize {
        self.default_chunk_size
            .unwrap_or(1024 * 1024)
            .clamp(32 * 1024, 1024 * 1024)
    }

    pub fn enable_resume(&self) -> bool {
        self.enable_resume.unwrap_or(true)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct TransferTask {
    pub task_id: String,
    pub kind: TaskKind,
    #[serde(default)]
    pub remote_path: Option<String>,
    #[serde(default)]
    pub local_path: Option<String>,
    #[serde(default)]
    pub local_paths: Vec<String>,
    #[serde(default)]
    pub remote_paths: Vec<String>,
    #[serde(default)]
    pub target_dir: Option<String>,
    pub priority: Option<u8>,
    pub chunk_size: Option<usize>,
}

impl TransferTask {
    pub fn priority(&self) -> u8 {
        self.priority.unwrap_or(5)
    }

    pub fn chunk_size_or(&self, fallback: usize) -> usize {
        self.chunk_size
            .unwrap_or(fallback)
            .clamp(32 * 1024, 1024 * 1024)
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskKind {
    Upload,
    Download,
    UploadBatch,
    DownloadBatch,
    EnsureParentDirs,
    ProbeRemoteFileSize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProgressSnapshot {
    pub task_id: String,
    pub status: TaskStatus,
    pub transferred_bytes: u64,
    pub total_bytes: Option<u64>,
    pub error_message: Option<String>,
    pub value_u64: Option<u64>,
    pub updated_at_ms: u64,
}

impl ProgressSnapshot {
    pub fn new(task_id: String, status: TaskStatus) -> Self {
        Self {
            task_id,
            status,
            transferred_bytes: 0,
            total_bytes: None,
            error_message: None,
            value_u64: None,
            updated_at_ms: now_ms(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct TransferEvent {
    pub event_type: EventType,
    pub task_id: String,
    pub transferred_bytes: Option<u64>,
    pub total_bytes: Option<u64>,
    pub value_u64: Option<u64>,
    pub message: Option<String>,
    pub timestamp_ms: u64,
}

impl TransferEvent {
    pub fn progress(task_id: &str, transferred: u64, total: Option<u64>) -> Self {
        Self {
            event_type: EventType::Progress,
            task_id: task_id.to_owned(),
            transferred_bytes: Some(transferred),
            total_bytes: total,
            value_u64: None,
            message: None,
            timestamp_ms: now_ms(),
        }
    }

    pub fn completion(
        task_id: &str,
        transferred: u64,
        total: Option<u64>,
        value: Option<u64>,
    ) -> Self {
        Self {
            event_type: EventType::Completion,
            task_id: task_id.to_owned(),
            transferred_bytes: Some(transferred),
            total_bytes: total,
            value_u64: value,
            message: None,
            timestamp_ms: now_ms(),
        }
    }

    pub fn error(task_id: &str, message: String) -> Self {
        Self {
            event_type: EventType::Error,
            task_id: task_id.to_owned(),
            transferred_bytes: None,
            total_bytes: None,
            value_u64: None,
            message: Some(message),
            timestamp_ms: now_ms(),
        }
    }

    pub fn cancelled(task_id: &str) -> Self {
        Self {
            event_type: EventType::Cancelled,
            task_id: task_id.to_owned(),
            transferred_bytes: None,
            total_bytes: None,
            value_u64: None,
            message: None,
            timestamp_ms: now_ms(),
        }
    }

    pub fn metrics(task_id: &str, speed_bytes_per_sec: u64) -> Self {
        Self {
            event_type: EventType::Metrics,
            task_id: task_id.to_owned(),
            transferred_bytes: Some(speed_bytes_per_sec),
            total_bytes: None,
            value_u64: None,
            message: None,
            timestamp_ms: now_ms(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    Progress,
    Completion,
    Error,
    Metrics,
    Cancelled,
}

#[derive(Debug, Clone)]
pub struct TaskExecutionOutput {
    pub transferred_bytes: u64,
    pub total_bytes: Option<u64>,
    pub value_u64: Option<u64>,
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_millis(0))
        .as_millis() as u64
}
