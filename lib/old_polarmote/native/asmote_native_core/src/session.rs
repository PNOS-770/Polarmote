use crate::error::{CoreError, CoreResult};
use crate::models::{
    now_ms, ProgressSnapshot, SessionConfig, TaskExecutionOutput, TaskStatus, TransferEvent,
    TransferTask,
};
use crate::scheduler::TaskScheduler;
use crate::transport::sftp::SftpConnection;
use once_cell::sync::Lazy;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, RwLock, RwLockReadGuard, RwLockWriteGuard};

const MAX_EVENT_BUFFER: usize = 4096;

pub struct SessionContext {
    config: SessionConfig,
    scheduler: TaskScheduler,
    events: Mutex<VecDeque<TransferEvent>>,
    progress: Mutex<HashMap<String, ProgressSnapshot>>,
    cancel_flags: Mutex<HashMap<String, Arc<AtomicBool>>>,
    connection_pool: Mutex<Vec<SftpConnection>>,
    connection_pool_limit: usize,
}

impl SessionContext {
    pub fn new(config: SessionConfig) -> Arc<Self> {
        let pool_limit = config.max_concurrency();
        Arc::new_cyclic(|weak| SessionContext {
            scheduler: TaskScheduler::new(weak.clone(), pool_limit),
            config,
            events: Mutex::new(VecDeque::new()),
            progress: Mutex::new(HashMap::new()),
            cancel_flags: Mutex::new(HashMap::new()),
            connection_pool: Mutex::new(Vec::new()),
            connection_pool_limit: pool_limit,
        })
    }

    pub fn config(&self) -> &SessionConfig {
        &self.config
    }

    pub fn enqueue(&self, task: TransferTask) -> CoreResult<()> {
        self.scheduler.enqueue(task)
    }

    pub fn cancel(&self, task_id: String) -> CoreResult<()> {
        self.scheduler.cancel(task_id)
    }

    pub fn shutdown(&self) {
        self.scheduler.shutdown();
        lock_unpoison(&self.connection_pool).clear();
    }

    pub fn poll_events(&self) -> Vec<TransferEvent> {
        let mut events = lock_unpoison(&self.events);
        events.drain(..).collect()
    }

    pub fn query_progress(&self, task_id: &str) -> Option<ProgressSnapshot> {
        lock_unpoison(&self.progress).get(task_id).cloned()
    }

    pub fn push_event(&self, event: TransferEvent) {
        let mut events = lock_unpoison(&self.events);
        if events.len() >= MAX_EVENT_BUFFER {
            events.pop_front();
        }
        events.push_back(event);
    }

    pub fn mark_task_queued(&self, task_id: &str) {
        self.update_snapshot(task_id, TaskStatus::Queued, None, None, None, None);
    }

    pub fn mark_task_running(&self, task_id: &str) {
        self.update_snapshot(task_id, TaskStatus::Running, None, None, None, None);
    }

    pub fn record_progress(&self, task_id: &str, transferred: u64, total: Option<u64>) {
        self.update_snapshot(
            task_id,
            TaskStatus::Running,
            Some(transferred),
            total,
            None,
            None,
        );
        self.push_event(TransferEvent::progress(task_id, transferred, total));
    }

    pub fn mark_task_completed(&self, task_id: &str, output: TaskExecutionOutput) {
        self.update_snapshot(
            task_id,
            TaskStatus::Completed,
            Some(output.transferred_bytes),
            output.total_bytes,
            None,
            output.value_u64,
        );
        self.push_event(TransferEvent::completion(
            task_id,
            output.transferred_bytes,
            output.total_bytes,
            output.value_u64,
        ));
    }

    pub fn mark_task_failed(&self, task_id: &str, message: String) {
        self.update_snapshot(
            task_id,
            TaskStatus::Failed,
            None,
            None,
            Some(message.clone()),
            None,
        );
        self.push_event(TransferEvent::error(task_id, message));
    }

    pub fn mark_task_cancelled(&self, task_id: &str) {
        self.update_snapshot(task_id, TaskStatus::Cancelled, None, None, None, None);
        self.push_event(TransferEvent::cancelled(task_id));
    }

    pub fn install_cancel_flag(&self, task_id: &str) -> Arc<AtomicBool> {
        let mut flags = lock_unpoison(&self.cancel_flags);
        if let Some(existing) = flags.get(task_id) {
            return Arc::clone(existing);
        }
        let flag = Arc::new(AtomicBool::new(false));
        flags.insert(task_id.to_owned(), Arc::clone(&flag));
        flag
    }

    pub fn set_cancel_requested(&self, task_id: &str) {
        let flags = lock_unpoison(&self.cancel_flags);
        if let Some(flag) = flags.get(task_id) {
            flag.store(true, Ordering::Relaxed);
        }
    }

    pub fn remove_cancel_flag(&self, task_id: &str) {
        let mut flags = lock_unpoison(&self.cancel_flags);
        flags.remove(task_id);
    }

    pub fn acquire_connection(&self) -> CoreResult<SftpConnection> {
        let mut pool = lock_unpoison(&self.connection_pool);
        if let Some(connection) = pool.pop() {
            return Ok(connection);
        }
        drop(pool);
        SftpConnection::connect(&self.config)
    }

    pub fn release_connection(&self, connection: SftpConnection) {
        let mut pool = lock_unpoison(&self.connection_pool);
        if pool.len() < self.connection_pool_limit {
            pool.push(connection);
        }
    }

    fn update_snapshot(
        &self,
        task_id: &str,
        status: TaskStatus,
        transferred: Option<u64>,
        total: Option<u64>,
        error: Option<String>,
        value_u64: Option<u64>,
    ) {
        let mut progress = lock_unpoison(&self.progress);
        let entry = progress
            .entry(task_id.to_owned())
            .or_insert_with(|| ProgressSnapshot::new(task_id.to_owned(), TaskStatus::Queued));
        entry.status = status;
        if let Some(transferred_bytes) = transferred {
            entry.transferred_bytes = transferred_bytes;
        }
        if total.is_some() {
            entry.total_bytes = total;
        }
        if error.is_some() {
            entry.error_message = error;
        }
        if value_u64.is_some() {
            entry.value_u64 = value_u64;
        }
        entry.updated_at_ms = now_ms();
    }
}

pub struct NativeTransferCore {
    sessions: RwLock<HashMap<u64, Arc<SessionContext>>>,
    next_session_id: AtomicU64,
}

impl NativeTransferCore {
    fn new() -> Self {
        Self {
            sessions: RwLock::new(HashMap::new()),
            next_session_id: AtomicU64::new(1),
        }
    }

    pub fn global() -> &'static Self {
        static INSTANCE: Lazy<NativeTransferCore> = Lazy::new(NativeTransferCore::new);
        &INSTANCE
    }

    pub fn create_session(&self, config: SessionConfig) -> u64 {
        let id = self.next_session_id.fetch_add(1, Ordering::Relaxed);
        let context = SessionContext::new(config);
        lock_write_unpoison(&self.sessions).insert(id, context);
        id
    }

    pub fn destroy_session(&self, session_id: u64) -> CoreResult<()> {
        let removed = lock_write_unpoison(&self.sessions).remove(&session_id);
        if let Some(context) = removed {
            context.shutdown();
            Ok(())
        } else {
            Err(CoreError::SessionNotFound(session_id))
        }
    }

    pub fn session(&self, session_id: u64) -> CoreResult<Arc<SessionContext>> {
        lock_read_unpoison(&self.sessions)
            .get(&session_id)
            .cloned()
            .ok_or(CoreError::SessionNotFound(session_id))
    }
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
