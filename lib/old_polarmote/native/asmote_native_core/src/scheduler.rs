use crate::error::{CoreError, CoreResult};
use crate::executor;
use crate::metrics::SpeedSampler;
use crate::models::{TransferEvent, TransferTask};
use crate::session::SessionContext;
use crossbeam_channel::{Receiver, Sender};
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashSet};
use std::sync::{Arc, Weak};
use std::thread;
use std::time::{Duration, Instant};

const PROGRESS_REPORT_MIN_DELTA_BYTES: u64 = 4 * 1024 * 1024;
const PROGRESS_REPORT_MAX_INTERVAL: Duration = Duration::from_millis(100);

#[derive(Debug)]
enum SchedulerCommand {
    Enqueue(TransferTask),
    Cancel(String),
    WorkerFinished(String),
    Shutdown,
}

pub struct TaskScheduler {
    tx: Sender<SchedulerCommand>,
}

impl TaskScheduler {
    pub fn new(session: Weak<SessionContext>, max_concurrency: usize) -> Self {
        let (tx, rx) = crossbeam_channel::unbounded();
        let loop_tx = tx.clone();
        thread::spawn(move || run_scheduler_loop(session, max_concurrency, loop_tx, rx));
        Self { tx }
    }

    pub fn enqueue(&self, task: TransferTask) -> CoreResult<()> {
        self.tx
            .send(SchedulerCommand::Enqueue(task))
            .map_err(|e| CoreError::Internal(format!("enqueue failed: {e}")))
    }

    pub fn cancel(&self, task_id: String) -> CoreResult<()> {
        self.tx
            .send(SchedulerCommand::Cancel(task_id))
            .map_err(|e| CoreError::Internal(format!("cancel failed: {e}")))
    }

    pub fn shutdown(&self) {
        let _ = self.tx.send(SchedulerCommand::Shutdown);
    }
}

#[derive(Debug)]
struct QueuedTask {
    priority: u8,
    seq: u64,
    task: TransferTask,
}

impl PartialEq for QueuedTask {
    fn eq(&self, other: &Self) -> bool {
        self.priority == other.priority && self.seq == other.seq
    }
}

impl Eq for QueuedTask {}

impl PartialOrd for QueuedTask {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for QueuedTask {
    fn cmp(&self, other: &Self) -> Ordering {
        self.priority
            .cmp(&other.priority)
            .then_with(|| other.seq.cmp(&self.seq))
    }
}

fn run_scheduler_loop(
    session: Weak<SessionContext>,
    max_concurrency: usize,
    scheduler_tx: Sender<SchedulerCommand>,
    scheduler_rx: Receiver<SchedulerCommand>,
) {
    let mut queue: BinaryHeap<QueuedTask> = BinaryHeap::new();
    let mut running: HashSet<String> = HashSet::new();
    let mut seq = 0u64;
    let mut shutting_down = false;

    loop {
        if !shutting_down {
            dispatch_ready_tasks(
                &session,
                max_concurrency,
                &mut queue,
                &mut running,
                &scheduler_tx,
            );
        }

        if shutting_down && running.is_empty() {
            break;
        }

        let command = match scheduler_rx.recv_timeout(Duration::from_millis(80)) {
            Ok(cmd) => cmd,
            Err(crossbeam_channel::RecvTimeoutError::Timeout) => continue,
            Err(crossbeam_channel::RecvTimeoutError::Disconnected) => break,
        };

        match command {
            SchedulerCommand::Enqueue(task) => {
                if let Some(ctx) = session.upgrade() {
                    ctx.mark_task_queued(&task.task_id);
                }
                queue.push(QueuedTask {
                    priority: task.priority(),
                    seq,
                    task,
                });
                seq = seq.wrapping_add(1);
            }
            SchedulerCommand::Cancel(task_id) => {
                let mut removed = false;
                if !queue.is_empty() {
                    let mut tasks = queue.into_vec();
                    tasks.retain(|queued| {
                        let keep = queued.task.task_id != task_id;
                        if !keep {
                            removed = true;
                        }
                        keep
                    });
                    queue = BinaryHeap::from(tasks);
                }

                if let Some(ctx) = session.upgrade() {
                    if removed {
                        ctx.mark_task_cancelled(&task_id);
                    } else {
                        ctx.set_cancel_requested(&task_id);
                    }
                }
            }
            SchedulerCommand::WorkerFinished(task_id) => {
                running.remove(&task_id);
                if let Some(ctx) = session.upgrade() {
                    ctx.remove_cancel_flag(&task_id);
                }
            }
            SchedulerCommand::Shutdown => {
                shutting_down = true;
                while let Some(task) = queue.pop() {
                    if let Some(ctx) = session.upgrade() {
                        ctx.mark_task_cancelled(&task.task.task_id);
                    }
                }
            }
        }
    }
}

fn dispatch_ready_tasks(
    session: &Weak<SessionContext>,
    max_concurrency: usize,
    queue: &mut BinaryHeap<QueuedTask>,
    running: &mut HashSet<String>,
    scheduler_tx: &Sender<SchedulerCommand>,
) {
    while running.len() < max_concurrency {
        let queued = match queue.pop() {
            Some(item) => item,
            None => return,
        };

        let Some(ctx) = session.upgrade() else {
            return;
        };

        let task = queued.task;
        let task_id = task.task_id.clone();
        running.insert(task_id.clone());
        ctx.mark_task_running(&task_id);

        let cancel_flag = ctx.install_cancel_flag(&task_id);
        let worker_ctx = Arc::clone(&ctx);
        let worker_tx = scheduler_tx.clone();
        thread::spawn(move || {
            let config = worker_ctx.config().clone();
            let mut sampler = SpeedSampler::new();
            let mut last_reported_bytes = 0u64;
            let mut last_reported_at = Instant::now();
            let mut has_reported_once = false;
            let mut pooled_connection = worker_ctx.acquire_connection().ok();
            let result = match pooled_connection.as_ref() {
                Some(connection) => executor::execute_task_with_connection(
                    &config,
                    &task,
                    cancel_flag.as_ref(),
                    |transferred, total| {
                        let is_done = total.map(|value| transferred >= value).unwrap_or(false);
                        let delta = transferred.saturating_sub(last_reported_bytes);
                        let elapsed = last_reported_at.elapsed();
                        let should_report = !has_reported_once
                            || is_done
                            || delta >= PROGRESS_REPORT_MIN_DELTA_BYTES
                            || elapsed >= PROGRESS_REPORT_MAX_INTERVAL;
                        if !should_report {
                            return Ok(());
                        }
                        has_reported_once = true;
                        last_reported_bytes = transferred;
                        last_reported_at = Instant::now();
                        worker_ctx.record_progress(&task.task_id, transferred, total);
                        if let Some(speed) = sampler.sample(transferred) {
                            worker_ctx.push_event(TransferEvent::metrics(&task.task_id, speed));
                        }
                        Ok(())
                    },
                    connection,
                ),
                None => executor::execute_task(
                    &config,
                    &task,
                    cancel_flag.as_ref(),
                    |transferred, total| {
                        let is_done = total.map(|value| transferred >= value).unwrap_or(false);
                        let delta = transferred.saturating_sub(last_reported_bytes);
                        let elapsed = last_reported_at.elapsed();
                        let should_report = !has_reported_once
                            || is_done
                            || delta >= PROGRESS_REPORT_MIN_DELTA_BYTES
                            || elapsed >= PROGRESS_REPORT_MAX_INTERVAL;
                        if !should_report {
                            return Ok(());
                        }
                        has_reported_once = true;
                        last_reported_bytes = transferred;
                        last_reported_at = Instant::now();
                        worker_ctx.record_progress(&task.task_id, transferred, total);
                        if let Some(speed) = sampler.sample(transferred) {
                            worker_ctx.push_event(TransferEvent::metrics(&task.task_id, speed));
                        }
                        Ok(())
                    },
                ),
            };

            if matches!(&result, Ok(_) | Err(CoreError::Cancelled)) {
                if let Some(connection) = pooled_connection.take() {
                    worker_ctx.release_connection(connection);
                }
            }

            match result {
                Ok(output) => worker_ctx.mark_task_completed(&task.task_id, output),
                Err(CoreError::Cancelled) => worker_ctx.mark_task_cancelled(&task.task_id),
                Err(error) => worker_ctx.mark_task_failed(&task.task_id, error.to_string()),
            }

            let _ = worker_tx.send(SchedulerCommand::WorkerFinished(task_id));
        });
    }
}
