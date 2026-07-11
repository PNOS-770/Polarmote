use crate::models::SessionConfig;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeConfig {
    pub max_sessions: usize,
    pub max_memory_cache: usize,
    pub default_qos: QosLevel,
    pub metrics_enabled: bool,
    pub event_buffer_size: usize,
    pub max_event_poll: usize,
    pub adaptive_min_parallel: usize,
    pub adaptive_max_parallel: usize,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            max_sessions: 64,
            max_memory_cache: 256 * 1024 * 1024,
            default_qos: QosLevel::Interactive,
            metrics_enabled: true,
            event_buffer_size: 20_000,
            max_event_poll: 512,
            adaptive_min_parallel: 1,
            adaptive_max_parallel: 16,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct SessionOpenRequest {
    pub config: SessionConfig,
    #[serde(default)]
    pub preferred_provider: ProviderKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)]
pub enum ProviderKind {
    Sftp,
}

impl Default for ProviderKind {
    fn default() -> Self {
        Self::Sftp
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QosLevel {
    Realtime,
    Interactive,
    Background,
    Bulk,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct GraphId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct NodeId(pub u64);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryPolicy {
    pub max_attempts: u32,
    pub base_backoff_ms: u64,
    pub max_backoff_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: 2,
            base_backoff_ms: 250,
            max_backoff_ms: 10_000,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NodeOperation {
    UploadFile {
        local_path: String,
        remote_path: String,
        chunk_size: Option<usize>,
    },
    DownloadFile {
        remote_path: String,
        local_path: String,
        chunk_size: Option<usize>,
    },
    UploadBatch {
        local_paths: Vec<String>,
        target_dir: String,
        chunk_size: Option<usize>,
    },
    DownloadBatch {
        remote_paths: Vec<String>,
        target_dir: String,
        chunk_size: Option<usize>,
    },
    MkdirRemote {
        path: String,
        mode: Option<u32>,
    },
    MkdirLocal {
        path: String,
    },
    RemoveRemote {
        path: String,
    },
    RemoveLocal {
        path: String,
    },
    EnsureRemoteParent {
        remote_path: String,
    },
    ProbeRemoteFileSize {
        remote_path: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferNode {
    pub node_id: NodeId,
    pub operation: NodeOperation,
    #[serde(default)]
    pub depends_on: Vec<NodeId>,
    #[serde(default)]
    pub qos: Option<QosLevel>,
    #[serde(default)]
    pub priority: Option<i32>,
    #[serde(default)]
    pub retry_policy: Option<RetryPolicy>,
    #[serde(default)]
    pub estimated_bytes: Option<u64>,
    #[serde(default)]
    pub display_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GraphMetadata {
    #[serde(default)]
    pub source_root: Option<String>,
    #[serde(default)]
    pub target_root: Option<String>,
    #[serde(default)]
    pub total_files: Option<u64>,
    #[serde(default)]
    pub total_dirs: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferGraph {
    #[serde(default)]
    pub graph_id: Option<GraphId>,
    #[serde(default)]
    pub name: Option<String>,
    pub nodes: Vec<TransferNode>,
    #[serde(default)]
    pub metadata: GraphMetadata,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GraphStatus {
    Submitted,
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)]
pub enum NodeStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Cancelled,
    Retrying,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    GraphSubmitted,
    GraphStarted,
    GraphCompleted,
    GraphFailed,
    GraphCancelled,
    NodeStarted,
    NodeProgress,
    NodeCompleted,
    NodeFailed,
    NodeRetrying,
    Metrics,
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferEvent {
    pub event_id: u64,
    pub session_id: u64,
    #[serde(default)]
    pub graph_id: Option<GraphId>,
    #[serde(default)]
    pub node_id: Option<NodeId>,
    pub timestamp_ms: u64,
    pub event_type: EventType,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub transferred_bytes: Option<u64>,
    #[serde(default)]
    pub total_bytes: Option<u64>,
    #[serde(default)]
    pub value_u64: Option<u64>,
    #[serde(default)]
    pub qos: Option<QosLevel>,
}

impl TransferEvent {
    pub fn new(session_id: u64, event_type: EventType) -> Self {
        Self {
            event_id: 0,
            session_id,
            graph_id: None,
            node_id: None,
            timestamp_ms: now_ms(),
            event_type,
            message: None,
            transferred_bytes: None,
            total_bytes: None,
            value_u64: None,
            qos: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventPollResponse {
    pub events: Vec<TransferEvent>,
    pub next_cursor: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMetricsSnapshot {
    pub session_id: u64,
    pub timestamp_ms: u64,
    pub active_graphs: usize,
    pub queued_nodes: usize,
    pub running_nodes: usize,
    pub completed_nodes: u64,
    pub failed_nodes: u64,
    pub bytes_transferred: u64,
    pub avg_throughput_bps: u64,
    pub recent_error_rate: f64,
    pub adaptive_parallelism: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphSummary {
    pub graph_id: GraphId,
    pub status: GraphStatus,
    pub submitted_at_ms: u64,
    #[serde(default)]
    pub started_at_ms: Option<u64>,
    #[serde(default)]
    pub finished_at_ms: Option<u64>,
    pub total_nodes: usize,
    pub completed_nodes: usize,
    pub failed_nodes: usize,
    pub cancelled_nodes: usize,
}

pub fn now_ms() -> u64 {
    use std::time::{Duration, SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_millis(0))
        .as_millis() as u64
}
