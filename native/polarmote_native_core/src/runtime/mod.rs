pub mod discovery;
pub mod event_metrics;
pub mod provider;
pub mod scheduler;

use crate::error::{CoreError, CoreResult};
use crate::models::SessionConfig;
use crate::models_v2::{
    now_ms, EventPollResponse, EventType, GraphId, GraphStatus, GraphSummary, NodeId,
    NodeOperation, QosLevel, RuntimeConfig, SessionMetricsSnapshot, TransferEvent, TransferGraph,
    TransferNode,
};
use crate::runtime::discovery::DiscoveryPipeline;
use crate::runtime::event_metrics::{
    CancelController, CancelToken, SessionEventLog, SessionMetrics,
};
use crate::runtime::provider::{ConnectionPool, SftpProvider, TransportProvider};
use crate::runtime::scheduler::{AdaptiveController, AdaptiveFeedback, AdaptiveSchedulerConfig};
use once_cell::sync::Lazy;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::thread;
use std::time::{Duration, Instant};

pub struct RuntimeRegistry {
    next_runtime_id: AtomicU64,
    runtimes: RwLock<HashMap<u64, Arc<TransferRuntime>>>,
}

impl RuntimeRegistry {
    fn new() -> Self {
        Self {
            next_runtime_id: AtomicU64::new(1),
            runtimes: RwLock::new(HashMap::new()),
        }
    }

    pub fn global() -> &'static Self {
        static INSTANCE: Lazy<RuntimeRegistry> = Lazy::new(RuntimeRegistry::new);
        &INSTANCE
    }

    pub fn create_runtime(&self, config: RuntimeConfig) -> u64 {
        let runtime_id = self.next_runtime_id.fetch_add(1, Ordering::Relaxed);
        let runtime = Arc::new(TransferRuntime::new(runtime_id, config));
        lock_write_unpoison(&self.runtimes).insert(runtime_id, runtime);
        runtime_id
    }

    pub fn destroy_runtime(&self, runtime_id: u64) -> CoreResult<()> {
        let removed = lock_write_unpoison(&self.runtimes).remove(&runtime_id);
        if removed.is_some() {
            Ok(())
        } else {
            Err(CoreError::Internal(format!(
                "runtime not found: {runtime_id}"
            )))
        }
    }

    pub fn runtime(&self, runtime_id: u64) -> CoreResult<Arc<TransferRuntime>> {
        lock_read_unpoison(&self.runtimes)
            .get(&runtime_id)
            .cloned()
            .ok_or_else(|| CoreError::Internal(format!("runtime not found: {runtime_id}")))
    }
}

pub struct TransferRuntime {
    #[allow(dead_code)]
    runtime_id: u64,
    config: RuntimeConfig,
    next_session_id: AtomicU64,
    sessions: RwLock<HashMap<u64, Arc<RuntimeSession>>>,
}

impl TransferRuntime {
    fn new(runtime_id: u64, config: RuntimeConfig) -> Self {
        Self {
            runtime_id,
            config,
            next_session_id: AtomicU64::new(1),
            sessions: RwLock::new(HashMap::new()),
        }
    }

    pub fn open_session(&self, config: SessionConfig) -> CoreResult<u64> {
        let mut sessions = lock_write_unpoison(&self.sessions);
        if sessions.len() >= self.config.max_sessions {
            return Err(CoreError::Internal(
                "runtime session limit reached".to_string(),
            ));
        }

        let session_id = self.next_session_id.fetch_add(1, Ordering::Relaxed);
        let session = Arc::new(RuntimeSession::new(session_id, config, &self.config));
        session.emit_info("session opened");
        sessions.insert(session_id, session);
        Ok(session_id)
    }

    pub fn close_session(&self, session_id: u64) -> CoreResult<()> {
        let removed = lock_write_unpoison(&self.sessions).remove(&session_id);
        if let Some(session) = removed {
            session.emit_info("session closed");
            Ok(())
        } else {
            Err(CoreError::SessionNotFound(session_id))
        }
    }

    pub fn submit_graph(&self, session_id: u64, graph: TransferGraph) -> CoreResult<u64> {
        let session = self.session(session_id)?;
        session.submit_graph(graph)
    }

    pub fn cancel_graph(&self, session_id: u64, graph_id: u64) -> CoreResult<()> {
        let session = self.session(session_id)?;
        session.cancel_graph(graph_id)
    }

    pub fn poll_events(
        &self,
        session_id: u64,
        cursor: u64,
        limit: usize,
    ) -> CoreResult<EventPollResponse> {
        let session = self.session(session_id)?;
        let effective_limit = limit.min(self.config.max_event_poll).max(1);
        Ok(session.event_log.poll(cursor, effective_limit))
    }

    pub fn query_metrics(&self, session_id: u64) -> CoreResult<SessionMetricsSnapshot> {
        let session = self.session(session_id)?;
        Ok(session.metrics.snapshot())
    }

    fn session(&self, session_id: u64) -> CoreResult<Arc<RuntimeSession>> {
        lock_read_unpoison(&self.sessions)
            .get(&session_id)
            .cloned()
            .ok_or(CoreError::SessionNotFound(session_id))
    }
}

struct RuntimeSession {
    session_id: u64,
    config: SessionConfig,
    event_log: Arc<SessionEventLog>,
    metrics: Arc<SessionMetrics>,
    cancel_controller: CancelController,
    provider_pool: ConnectionPool<SftpProvider>,
    adaptive_config: AdaptiveSchedulerConfig,
    next_graph_id: AtomicU64,
    graph_summaries: Mutex<HashMap<u64, GraphSummary>>,
}

impl RuntimeSession {
    fn new(session_id: u64, config: SessionConfig, runtime_config: &RuntimeConfig) -> Self {
        let event_log = Arc::new(SessionEventLog::new(
            session_id,
            runtime_config.event_buffer_size,
        ));
        let metrics = Arc::new(SessionMetrics::new(session_id));

        Self {
            session_id,
            provider_pool: ConnectionPool::new(
                config.clone(),
                config.max_concurrency(),
                Duration::from_secs(180),
            ),
            adaptive_config: AdaptiveSchedulerConfig {
                min_parallel: runtime_config.adaptive_min_parallel.max(1),
                max_parallel: runtime_config.adaptive_max_parallel.max(1),
                ..AdaptiveSchedulerConfig::default()
            },
            cancel_controller: CancelController::new(),
            next_graph_id: AtomicU64::new(1),
            graph_summaries: Mutex::new(HashMap::new()),
            config,
            event_log,
            metrics,
        }
    }

    fn submit_graph(self: &Arc<Self>, mut graph: TransferGraph) -> CoreResult<u64> {
        if graph.nodes.is_empty() {
            return Err(CoreError::Internal(
                "graph nodes cannot be empty".to_string(),
            ));
        }

        let graph_id = graph
            .graph_id
            .map(|value| value.0)
            .filter(|value| *value > 0)
            .unwrap_or_else(|| self.next_graph_id.fetch_add(1, Ordering::Relaxed));
        graph.graph_id = Some(GraphId(graph_id));

        graph.nodes = self.expand_batch_nodes(graph.nodes)?;
        if graph.nodes.is_empty() {
            return Err(CoreError::Internal(
                "graph nodes cannot be empty after expansion".to_string(),
            ));
        }

        normalize_graph_node_ids(&mut graph.nodes)?;
        validate_graph(&graph.nodes)?;

        let total_nodes = graph.nodes.len();
        let summary = GraphSummary {
            graph_id: GraphId(graph_id),
            status: GraphStatus::Submitted,
            submitted_at_ms: now_ms(),
            started_at_ms: None,
            finished_at_ms: None,
            total_nodes,
            completed_nodes: 0,
            failed_nodes: 0,
            cancelled_nodes: 0,
        };
        lock_unpoison(&self.graph_summaries).insert(graph_id, summary);

        self.push_graph_event(
            graph_id,
            EventType::GraphSubmitted,
            Some("graph submitted".to_string()),
        );

        let token = self.cancel_controller.register_graph(graph_id);
        let session = Arc::clone(self);

        thread::spawn(move || {
            session.execute_graph(graph_id, graph, token);
        });

        Ok(graph_id)
    }

    fn expand_batch_nodes(&self, nodes: Vec<TransferNode>) -> CoreResult<Vec<TransferNode>> {
        let mut expanded = Vec::with_capacity(nodes.len());
        let mut pooled_provider = None;

        for node in nodes {
            match &node.operation {
                NodeOperation::UploadBatch {
                    local_paths,
                    target_dir,
                    ..
                } => {
                    let qos = node.qos.unwrap_or(QosLevel::Interactive);
                    match DiscoveryPipeline::build_upload_graph(local_paths, target_dir, qos) {
                        Ok(graph) if !graph.nodes.is_empty() => {
                            for discovered in graph.nodes {
                                expanded.push(merge_discovered_node(&node, discovered));
                            }
                        }
                        Ok(_) => {
                            expanded.push(node);
                        }
                        Err(error) => {
                            self.emit_info(&format!("batch expansion fallback (upload): {error}"));
                            expanded.push(node);
                        }
                    }
                }
                NodeOperation::DownloadBatch {
                    remote_paths,
                    target_dir,
                    ..
                } => {
                    if pooled_provider.is_none() {
                        match self.provider_pool.acquire() {
                            Ok(provider) => pooled_provider = Some(provider),
                            Err(error) => {
                                self.emit_info(&format!(
                                    "batch expansion fallback (download acquire): {error}"
                                ));
                                expanded.push(node);
                                continue;
                            }
                        }
                    }

                    let provider = pooled_provider
                        .as_mut()
                        .expect("pooled provider should exist")
                        .provider_mut();
                    let qos = node.qos.unwrap_or(QosLevel::Interactive);
                    match DiscoveryPipeline::build_download_graph(
                        provider,
                        remote_paths,
                        target_dir,
                        qos,
                    ) {
                        Ok(graph) if !graph.nodes.is_empty() => {
                            for discovered in graph.nodes {
                                expanded.push(merge_discovered_node(&node, discovered));
                            }
                        }
                        Ok(_) => {
                            expanded.push(node);
                        }
                        Err(error) => {
                            self.emit_info(&format!(
                                "batch expansion fallback (download): {error}"
                            ));
                            expanded.push(node);
                        }
                    }
                }
                _ => expanded.push(node),
            }
        }

        Ok(expanded)
    }

    fn cancel_graph(&self, graph_id: u64) -> CoreResult<()> {
        if self.cancel_controller.get_graph_token(graph_id).is_none() {
            return Err(CoreError::Internal(format!("graph not found: {graph_id}")));
        }
        self.cancel_controller.cancel_graph(graph_id);
        self.push_graph_event(
            graph_id,
            EventType::GraphCancelled,
            Some("graph cancellation requested".to_string()),
        );
        Ok(())
    }

    fn emit_info(&self, message: &str) {
        let mut event = TransferEvent::new(self.session_id, EventType::Info);
        event.message = Some(message.to_string());
        self.event_log.push(event);
    }

    fn push_graph_event(&self, graph_id: u64, event_type: EventType, message: Option<String>) {
        let mut event = TransferEvent::new(self.session_id, event_type);
        event.graph_id = Some(GraphId(graph_id));
        event.message = message;
        self.event_log.push(event);
    }

    fn push_node_event(
        &self,
        graph_id: u64,
        node_id: NodeId,
        event_type: EventType,
        message: Option<String>,
        transferred: Option<u64>,
        total: Option<u64>,
        value_u64: Option<u64>,
        qos: Option<QosLevel>,
    ) {
        let mut event = TransferEvent::new(self.session_id, event_type);
        event.graph_id = Some(GraphId(graph_id));
        event.node_id = Some(node_id);
        event.message = message;
        event.transferred_bytes = transferred;
        event.total_bytes = total;
        event.value_u64 = value_u64;
        event.qos = qos;
        self.event_log.push(event);
    }

    fn execute_graph(self: Arc<Self>, graph_id: u64, graph: TransferGraph, token: CancelToken) {
        self.metrics.mark_graph_started();
        self.set_graph_status(graph_id, GraphStatus::Running);
        self.push_graph_event(
            graph_id,
            EventType::GraphStarted,
            Some("graph started".to_string()),
        );

        let mut nodes: HashMap<NodeId, TransferNode> = HashMap::new();
        for node in graph.nodes {
            nodes.insert(node.node_id, node);
        }

        let total_nodes = nodes.len();
        let mut pending: HashSet<NodeId> = nodes.keys().copied().collect();
        let mut running: HashSet<NodeId> = HashSet::new();
        let mut completed: HashSet<NodeId> = HashSet::new();
        let mut failed: HashSet<NodeId> = HashSet::new();
        let mut cancelled: HashSet<NodeId> = HashSet::new();
        let mut attempts: HashMap<NodeId, u32> = HashMap::new();
        let mut retry_after: HashMap<NodeId, Instant> = HashMap::new();

        let mut total_transferred_bytes = 0u64;
        let mut adaptive = AdaptiveController::new(self.adaptive_config.clone());

        let (tx, rx) = mpsc::channel::<NodeWorkerResult>();

        while completed.len() + failed.len() + cancelled.len() < total_nodes {
            if token.is_cancelled() {
                for node_id in pending.drain() {
                    cancelled.insert(node_id);
                    self.push_node_event(
                        graph_id,
                        node_id,
                        EventType::NodeFailed,
                        Some("cancelled before execution".to_string()),
                        None,
                        None,
                        None,
                        None,
                    );
                }
                break;
            }

            let parallel = adaptive.current_parallelism();
            self.metrics.set_adaptive_parallelism(parallel);

            let ready = collect_ready_nodes(
                &nodes,
                &pending,
                &completed,
                &retry_after,
                &failed,
                &cancelled,
            );

            let mut ready_sorted = ready;
            ready_sorted.sort_by_key(|node_id| {
                let node = nodes.get(node_id).expect("ready node must exist");
                effective_priority(node)
            });

            for node_id in ready_sorted {
                if running.len() >= parallel {
                    break;
                }

                pending.remove(&node_id);
                running.insert(node_id);

                if let Some(node) = nodes.get(&node_id) {
                    self.push_node_event(
                        graph_id,
                        node_id,
                        EventType::NodeStarted,
                        node.display_name.clone(),
                        None,
                        None,
                        None,
                        node.qos,
                    );
                }

                let tx_clone = tx.clone();
                let session = Arc::clone(&self);
                let token_clone = token.clone();
                let node = nodes.get(&node_id).expect("node should exist").clone();

                thread::spawn(move || {
                    let started = Instant::now();
                    let result = session.execute_node(graph_id, &node, &token_clone);
                    let elapsed = started.elapsed();
                    let _ = tx_clone.send(NodeWorkerResult {
                        node_id,
                        result,
                        elapsed,
                    });
                });
            }

            self.metrics.set_queue_depth(pending.len(), running.len());
            adaptive.note_queue_pressure(pending.len(), running.len());

            if running.is_empty() {
                if pending.is_empty() {
                    break;
                }

                // All pending nodes are waiting for retry cooldown — wait
                // for the earliest timer instead of declaring a deadlock.
                let all_in_retry_cooldown =
                    pending.iter().all(|id| retry_after.contains_key(id));
                if all_in_retry_cooldown {
                    let earliest = retry_after
                        .values()
                        .min()
                        .copied()
                        .unwrap_or_else(Instant::now);
                    let wait = earliest.saturating_duration_since(Instant::now());
                    if !wait.is_zero() {
                        let deadline = Instant::now() + wait;
                        while Instant::now() < deadline {
                            if token.is_cancelled() {
                                break;
                            }
                            thread::sleep(Duration::from_millis(200));
                        }
                    }
                    continue;
                }

                // Dependency deadlock (e.g. parents failed and children keep waiting).
                for node_id in pending.drain() {
                    failed.insert(node_id);
                    self.push_node_event(
                        graph_id,
                        node_id,
                        EventType::NodeFailed,
                        Some("blocked by failed dependencies".to_string()),
                        None,
                        None,
                        None,
                        None,
                    );
                    self.metrics.record_node_failed();
                }
                break;
            }

            let worker = match rx.recv_timeout(Duration::from_millis(200)) {
                Ok(value) => value,
                Err(mpsc::RecvTimeoutError::Timeout) => continue,
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            };

            running.remove(&worker.node_id);
            let node = match nodes.get(&worker.node_id) {
                Some(value) => value,
                None => continue,
            };

            match worker.result {
                Ok(output) => {
                    retry_after.remove(&worker.node_id);
                    completed.insert(worker.node_id);
                    total_transferred_bytes =
                        total_transferred_bytes.saturating_add(output.transferred_bytes);
                    self.metrics.record_node_completed(output.transferred_bytes);
                    self.metrics.record_progress(total_transferred_bytes);

                    let throughput =
                        throughput_from_output(output.transferred_bytes, worker.elapsed);
                    adaptive.update(AdaptiveFeedback {
                        success: true,
                        throughput_bps: Some(throughput),
                        transient_error: false,
                    });

                    self.push_node_event(
                        graph_id,
                        worker.node_id,
                        EventType::NodeCompleted,
                        None,
                        Some(output.transferred_bytes),
                        output.total_bytes,
                        output.value_u64,
                        node.qos,
                    );
                }
                Err(CoreError::Cancelled) => {
                    cancelled.insert(worker.node_id);
                    self.push_node_event(
                        graph_id,
                        worker.node_id,
                        EventType::NodeFailed,
                        Some("cancelled".to_string()),
                        None,
                        None,
                        None,
                        node.qos,
                    );
                    adaptive.update(AdaptiveFeedback {
                        success: false,
                        throughput_bps: None,
                        transient_error: true,
                    });
                }
                Err(error) => {
                    let attempt = attempts.entry(worker.node_id).or_insert(0);
                    *attempt += 1;
                    let retry_policy = node.retry_policy.clone().unwrap_or_default();
                    let has_retry = *attempt <= retry_policy.max_attempts;

                    if has_retry && !token.is_cancelled() {
                        let wait = compute_backoff(&retry_policy, *attempt);
                        retry_after.insert(worker.node_id, Instant::now() + wait);
                        pending.insert(worker.node_id);
                        self.push_node_event(
                            graph_id,
                            worker.node_id,
                            EventType::NodeRetrying,
                            Some(format!("attempt={}, wait_ms={}", attempt, wait.as_millis())),
                            None,
                            None,
                            Some(*attempt as u64),
                            node.qos,
                        );
                    } else {
                        failed.insert(worker.node_id);
                        self.metrics.record_node_failed();
                        self.push_node_event(
                            graph_id,
                            worker.node_id,
                            EventType::NodeFailed,
                            Some(error.to_string()),
                            None,
                            None,
                            None,
                            node.qos,
                        );
                    }

                    adaptive.update(AdaptiveFeedback {
                        success: false,
                        throughput_bps: None,
                        transient_error: is_transient_error(&error),
                    });
                }
            }

            self.update_graph_progress(graph_id, completed.len(), failed.len(), cancelled.len());
        }

        self.metrics.mark_graph_finished();
        self.cancel_controller.unregister_graph(graph_id);

        let status = if token.is_cancelled() {
            GraphStatus::Cancelled
        } else if !failed.is_empty() {
            GraphStatus::Failed
        } else {
            GraphStatus::Completed
        };

        self.set_graph_status(graph_id, status);

        match status {
            GraphStatus::Completed => {
                self.push_graph_event(
                    graph_id,
                    EventType::GraphCompleted,
                    Some("graph completed".to_string()),
                );
            }
            GraphStatus::Failed => {
                self.push_graph_event(
                    graph_id,
                    EventType::GraphFailed,
                    Some(format!("graph finished with {} failed nodes", failed.len())),
                );
            }
            GraphStatus::Cancelled => {
                self.push_graph_event(
                    graph_id,
                    EventType::GraphCancelled,
                    Some("graph cancelled".to_string()),
                );
            }
            _ => {}
        }
    }

    fn execute_node(
        &self,
        graph_id: u64,
        node: &TransferNode,
        token: &CancelToken,
    ) -> CoreResult<crate::models::TaskExecutionOutput> {
        let mut pool = self.provider_pool.acquire()?;
        let provider = pool.provider_mut();
        let cancelled_flag = token.as_flag();

        // Helper: run a provider operation and disconnect the provider on
        // error so the broken connection is not returned to the idle pool.
        macro_rules! try_provider {
            ($expr:expr) => {{
                let result = $expr;
                if result.is_err() {
                    provider.disconnect();
                }
                result
            }};
        }

        match &node.operation {
            NodeOperation::UploadFile {
                local_path,
                remote_path,
                chunk_size,
            } => try_provider!(provider.upload(
                local_path,
                remote_path,
                chunk_size.unwrap_or(self.config.default_chunk_size()),
                cancelled_flag.as_ref(),
                &mut |transferred, total| {
                    self.push_node_event(
                        graph_id,
                        node.node_id,
                        EventType::NodeProgress,
                        None,
                        Some(transferred),
                        total,
                        None,
                        node.qos,
                    );
                    Ok(())
                },
            )),
            NodeOperation::DownloadFile {
                remote_path,
                local_path,
                chunk_size,
            } => {
                let output = try_provider!(provider.download(
                    remote_path,
                    local_path,
                    chunk_size.unwrap_or(self.config.default_chunk_size()),
                    cancelled_flag.as_ref(),
                    &mut |transferred, total| {
                        self.push_node_event(
                            graph_id,
                            node.node_id,
                            EventType::NodeProgress,
                            None,
                            Some(transferred),
                            total,
                            None,
                            node.qos,
                        );
                        Ok(())
                    },
                ))?;
                Ok(output)
            }
            NodeOperation::UploadBatch {
                local_paths,
                target_dir,
                chunk_size,
            } => try_provider!(provider.upload_batch(
                &self.config,
                local_paths,
                target_dir,
                chunk_size.unwrap_or(self.config.default_chunk_size()),
                cancelled_flag.as_ref(),
                &mut |transferred, total| {
                    self.push_node_event(
                        graph_id,
                        node.node_id,
                        EventType::NodeProgress,
                        None,
                        Some(transferred),
                        total,
                        None,
                        node.qos,
                    );
                    Ok(())
                },
            )),
            NodeOperation::DownloadBatch {
                remote_paths,
                target_dir,
                chunk_size,
            } => try_provider!(provider.download_batch(
                &self.config,
                remote_paths,
                target_dir,
                chunk_size.unwrap_or(self.config.default_chunk_size()),
                cancelled_flag.as_ref(),
                &mut |transferred, total| {
                    self.push_node_event(
                        graph_id,
                        node.node_id,
                        EventType::NodeProgress,
                        None,
                        Some(transferred),
                        total,
                        None,
                        node.qos,
                    );
                    Ok(())
                },
            )),
            NodeOperation::MkdirRemote { path, mode } => {
                try_provider!(provider.mkdir_remote(path, mode.unwrap_or(0o755)))?;
                Ok(crate::models::TaskExecutionOutput {
                    transferred_bytes: 0,
                    total_bytes: None,
                    value_u64: None,
                })
            }
            NodeOperation::MkdirLocal { path } => {
                fs::create_dir_all(path)?;
                Ok(crate::models::TaskExecutionOutput {
                    transferred_bytes: 0,
                    total_bytes: None,
                    value_u64: None,
                })
            }
            NodeOperation::RemoveRemote { path } => {
                try_provider!(provider.remove_remote(path))?;
                Ok(crate::models::TaskExecutionOutput {
                    transferred_bytes: 0,
                    total_bytes: None,
                    value_u64: None,
                })
            }
            NodeOperation::RemoveLocal { path } => {
                let path_ref = std::path::Path::new(path);
                if path_ref.is_dir() {
                    fs::remove_dir_all(path_ref)?;
                } else if path_ref.exists() {
                    fs::remove_file(path_ref)?;
                }
                Ok(crate::models::TaskExecutionOutput {
                    transferred_bytes: 0,
                    total_bytes: None,
                    value_u64: None,
                })
            }
            NodeOperation::EnsureRemoteParent { remote_path } => {
                if let Some(parent) = std::path::Path::new(remote_path).parent() {
                    let parent = parent.to_string_lossy().replace('\\', "/");
                    if !parent.is_empty() {
                        provider.mkdir_remote(&parent, 0o755)?;
                    }
                }
                Ok(crate::models::TaskExecutionOutput {
                    transferred_bytes: 0,
                    total_bytes: None,
                    value_u64: None,
                })
            }
            NodeOperation::ProbeRemoteFileSize { remote_path } => {
                provider.probe_remote_file_size(remote_path, cancelled_flag.as_ref())
            }
        }
    }

    fn set_graph_status(&self, graph_id: u64, status: GraphStatus) {
        let mut summaries = lock_unpoison(&self.graph_summaries);
        if let Some(summary) = summaries.get_mut(&graph_id) {
            summary.status = status;
            match status {
                GraphStatus::Running => {
                    summary.started_at_ms = Some(now_ms());
                }
                GraphStatus::Completed | GraphStatus::Failed | GraphStatus::Cancelled => {
                    summary.finished_at_ms = Some(now_ms());
                }
                _ => {}
            }
        }
    }

    fn update_graph_progress(
        &self,
        graph_id: u64,
        completed: usize,
        failed: usize,
        cancelled: usize,
    ) {
        let mut summaries = lock_unpoison(&self.graph_summaries);
        if let Some(summary) = summaries.get_mut(&graph_id) {
            summary.completed_nodes = completed;
            summary.failed_nodes = failed;
            summary.cancelled_nodes = cancelled;
        }
    }
}

fn merge_discovered_node(template: &TransferNode, mut discovered: TransferNode) -> TransferNode {
    if !template.depends_on.is_empty() {
        let mut deps = template.depends_on.clone();
        deps.extend(discovered.depends_on.iter().copied());
        deps.sort_by_key(|value| value.0);
        deps.dedup_by_key(|value| value.0);
        discovered.depends_on = deps;
    }
    if template.qos.is_some() {
        discovered.qos = template.qos;
    }
    if template.priority.is_some() {
        discovered.priority = template.priority;
    }
    if template.retry_policy.is_some() {
        discovered.retry_policy = template.retry_policy.clone();
    }
    if discovered.display_name.is_none() {
        discovered.display_name = template.display_name.clone();
    }
    discovered
}

struct NodeWorkerResult {
    node_id: NodeId,
    result: CoreResult<crate::models::TaskExecutionOutput>,
    elapsed: Duration,
}

fn effective_priority(node: &TransferNode) -> i64 {
    let qos_boost = match node.qos.unwrap_or(QosLevel::Interactive) {
        QosLevel::Realtime => -1000,
        QosLevel::Interactive => -100,
        QosLevel::Background => 100,
        QosLevel::Bulk => 200,
    };
    i64::from(node.priority.unwrap_or(0)) + i64::from(qos_boost)
}

fn normalize_graph_node_ids(nodes: &mut [TransferNode]) -> CoreResult<()> {
    let mut next = 1u64;
    let mut seen = HashSet::new();

    for node in nodes.iter_mut() {
        if node.node_id.0 == 0 {
            while seen.contains(&next) {
                next += 1;
            }
            node.node_id = NodeId(next);
        }
        if !seen.insert(node.node_id.0) {
            return Err(CoreError::Internal(format!(
                "duplicate node id: {}",
                node.node_id.0
            )));
        }
        if node.retry_policy.is_none() {
            node.retry_policy = Some(Default::default());
        }
        next = next.max(node.node_id.0 + 1);
    }

    Ok(())
}

fn validate_graph(nodes: &[TransferNode]) -> CoreResult<()> {
    let ids: HashSet<NodeId> = nodes.iter().map(|node| node.node_id).collect();
    for node in nodes {
        for dep in &node.depends_on {
            if !ids.contains(dep) {
                return Err(CoreError::Internal(format!(
                    "node {} depends on missing node {}",
                    node.node_id.0, dep.0
                )));
            }
        }
    }
    Ok(())
}

fn collect_ready_nodes(
    nodes: &HashMap<NodeId, TransferNode>,
    pending: &HashSet<NodeId>,
    completed: &HashSet<NodeId>,
    retry_after: &HashMap<NodeId, Instant>,
    failed: &HashSet<NodeId>,
    cancelled: &HashSet<NodeId>,
) -> Vec<NodeId> {
    let now = Instant::now();
    pending
        .iter()
        .filter(|node_id| {
            let Some(node) = nodes.get(node_id) else {
                return false;
            };
            if let Some(deadline) = retry_after.get(node_id) {
                if *deadline > now {
                    return false;
                }
            }
            node.depends_on.iter().all(|dep| completed.contains(dep))
                && !node
                    .depends_on
                    .iter()
                    .any(|dep| failed.contains(dep) || cancelled.contains(dep))
        })
        .copied()
        .collect()
}

fn compute_backoff(policy: &crate::models_v2::RetryPolicy, attempt: u32) -> Duration {
    let factor = 2u64.saturating_pow(attempt.saturating_sub(1));
    let delay = policy
        .base_backoff_ms
        .saturating_mul(factor)
        .min(policy.max_backoff_ms.max(policy.base_backoff_ms));
    Duration::from_millis(delay)
}

fn throughput_from_output(bytes: u64, elapsed: Duration) -> u64 {
    if elapsed.is_zero() {
        return 0;
    }
    (bytes as f64 / elapsed.as_secs_f64()) as u64
}

fn is_transient_error(error: &CoreError) -> bool {
    let text = error.to_string().to_ascii_lowercase();
    text.contains("timeout")
        || text.contains("tempor")
        || text.contains("would block")
        || text.contains("again")
        || text.contains("handshake")
        || text.contains("connection")
}

fn lock_unpoison<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn lock_read_unpoison<T>(rwlock: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    match rwlock.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn lock_write_unpoison<T>(rwlock: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    match rwlock.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}
