use crate::models_v2::{now_ms, EventPollResponse, SessionMetricsSnapshot, TransferEvent};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

pub struct SessionEventLog {
    session_id: u64,
    max_size: usize,
    next_event_id: AtomicU64,
    events: Mutex<VecDeque<TransferEvent>>,
}

impl SessionEventLog {
    pub fn new(session_id: u64, max_size: usize) -> Self {
        Self {
            session_id,
            max_size: max_size.max(256),
            next_event_id: AtomicU64::new(1),
            events: Mutex::new(VecDeque::with_capacity(max_size.max(256))),
        }
    }

    pub fn push(&self, mut event: TransferEvent) -> u64 {
        let id = self.next_event_id.fetch_add(1, Ordering::Relaxed);
        event.event_id = id;
        event.session_id = self.session_id;
        if event.timestamp_ms == 0 {
            event.timestamp_ms = now_ms();
        }

        let mut events = lock_unpoison(&self.events);
        if events.len() >= self.max_size {
            events.pop_front();
        }
        events.push_back(event);
        id
    }

    pub fn poll(&self, after_cursor: u64, limit: usize) -> EventPollResponse {
        let limit = limit.max(1);
        let events = lock_unpoison(&self.events);

        let mut result = Vec::new();
        let mut next_cursor = after_cursor;
        for event in events.iter() {
            if event.event_id <= after_cursor {
                continue;
            }
            next_cursor = event.event_id;
            result.push(event.clone());
            if result.len() >= limit {
                break;
            }
        }

        EventPollResponse {
            events: result,
            next_cursor,
        }
    }

    #[allow(dead_code)]
    pub fn latest_cursor(&self) -> u64 {
        let events = lock_unpoison(&self.events);
        events.back().map(|item| item.event_id).unwrap_or(0)
    }
}

#[derive(Default)]
struct MetricsState {
    started_at: Option<Instant>,
    active_graphs: usize,
    queued_nodes: usize,
    running_nodes: usize,
    completed_nodes: u64,
    failed_nodes: u64,
    bytes_transferred: u64,
    samples: VecDeque<(Instant, u64)>,
    recent_error_window: VecDeque<bool>,
    adaptive_parallelism: usize,
}

pub struct SessionMetrics {
    session_id: u64,
    state: Mutex<MetricsState>,
}

impl SessionMetrics {
    pub fn new(session_id: u64) -> Self {
        Self {
            session_id,
            state: Mutex::new(MetricsState {
                adaptive_parallelism: 1,
                ..MetricsState::default()
            }),
        }
    }

    pub fn mark_graph_started(&self) {
        let mut state = lock_unpoison(&self.state);
        if state.started_at.is_none() {
            state.started_at = Some(Instant::now());
        }
        state.active_graphs += 1;
    }

    pub fn mark_graph_finished(&self) {
        let mut state = lock_unpoison(&self.state);
        state.active_graphs = state.active_graphs.saturating_sub(1);
    }

    pub fn set_queue_depth(&self, queued: usize, running: usize) {
        let mut state = lock_unpoison(&self.state);
        state.queued_nodes = queued;
        state.running_nodes = running;
    }

    pub fn set_adaptive_parallelism(&self, value: usize) {
        let mut state = lock_unpoison(&self.state);
        state.adaptive_parallelism = value.max(1);
    }

    pub fn record_progress(&self, transferred_bytes: u64) {
        let mut state = lock_unpoison(&self.state);
        state.bytes_transferred = transferred_bytes;
        let now = Instant::now();
        state.samples.push_back((now, transferred_bytes));
        while state.samples.len() > 20 {
            state.samples.pop_front();
        }
    }

    pub fn record_node_completed(&self, bytes: u64) {
        let mut state = lock_unpoison(&self.state);
        state.completed_nodes = state.completed_nodes.saturating_add(1);
        state.bytes_transferred = state.bytes_transferred.saturating_add(bytes);
        state.recent_error_window.push_back(false);
        while state.recent_error_window.len() > 100 {
            state.recent_error_window.pop_front();
        }
    }

    pub fn record_node_failed(&self) {
        let mut state = lock_unpoison(&self.state);
        state.failed_nodes = state.failed_nodes.saturating_add(1);
        state.recent_error_window.push_back(true);
        while state.recent_error_window.len() > 100 {
            state.recent_error_window.pop_front();
        }
    }

    pub fn snapshot(&self) -> SessionMetricsSnapshot {
        let state = lock_unpoison(&self.state);
        let throughput = estimate_throughput_bps(&state.samples);
        let error_rate = if state.recent_error_window.is_empty() {
            0.0
        } else {
            let failures = state
                .recent_error_window
                .iter()
                .filter(|item| **item)
                .count();
            failures as f64 / state.recent_error_window.len() as f64
        };

        SessionMetricsSnapshot {
            session_id: self.session_id,
            timestamp_ms: now_ms(),
            active_graphs: state.active_graphs,
            queued_nodes: state.queued_nodes,
            running_nodes: state.running_nodes,
            completed_nodes: state.completed_nodes,
            failed_nodes: state.failed_nodes,
            bytes_transferred: state.bytes_transferred,
            avg_throughput_bps: throughput,
            recent_error_rate: error_rate,
            adaptive_parallelism: state.adaptive_parallelism,
        }
    }
}

fn estimate_throughput_bps(samples: &VecDeque<(Instant, u64)>) -> u64 {
    if samples.len() < 2 {
        return 0;
    }
    let (start_t, start_b) = match samples.front() {
        Some(value) => value,
        None => return 0,
    };
    let (end_t, end_b) = match samples.back() {
        Some(value) => value,
        None => return 0,
    };
    let elapsed = end_t.duration_since(*start_t).as_secs_f64();
    if elapsed <= 0.0 {
        return 0;
    }
    ((end_b.saturating_sub(*start_b)) as f64 / elapsed).max(0.0) as u64
}

#[derive(Clone)]
pub struct CancelToken {
    inner: Arc<AtomicBool>,
}

impl CancelToken {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn cancel(&self) {
        self.inner.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.load(Ordering::Relaxed)
    }

    pub fn as_flag(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.inner)
    }
}

pub struct CancelController {
    graph_tokens: Mutex<HashMap<u64, CancelToken>>,
}

impl CancelController {
    pub fn new() -> Self {
        Self {
            graph_tokens: Mutex::new(HashMap::new()),
        }
    }

    pub fn register_graph(&self, graph_id: u64) -> CancelToken {
        let mut map = lock_unpoison(&self.graph_tokens);
        let token = CancelToken::new();
        map.insert(graph_id, token.clone());
        token
    }

    pub fn get_graph_token(&self, graph_id: u64) -> Option<CancelToken> {
        let map = lock_unpoison(&self.graph_tokens);
        map.get(&graph_id).cloned()
    }

    pub fn cancel_graph(&self, graph_id: u64) {
        let map = lock_unpoison(&self.graph_tokens);
        if let Some(token) = map.get(&graph_id) {
            token.cancel();
        }
    }

    pub fn unregister_graph(&self, graph_id: u64) {
        let mut map = lock_unpoison(&self.graph_tokens);
        map.remove(&graph_id);
    }
}

fn lock_unpoison<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}
