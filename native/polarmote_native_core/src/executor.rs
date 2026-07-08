use crate::error::CoreResult;
use crate::models::{SessionConfig, TaskExecutionOutput, TaskKind, TransferTask};
use crate::transport;
use crate::transport::sftp::SftpConnection;
use std::sync::atomic::AtomicBool;

fn required_remote_path(task: &TransferTask, context: &str) -> CoreResult<String> {
    task.remote_path
        .clone()
        .ok_or_else(|| crate::error::CoreError::Internal(format!("{context} missing remote_path")))
}

fn required_local_path(task: &TransferTask, context: &str) -> CoreResult<String> {
    task.local_path
        .clone()
        .ok_or_else(|| crate::error::CoreError::Internal(format!("{context} missing local_path")))
}

fn required_target_dir(task: &TransferTask, context: &str) -> CoreResult<String> {
    task.target_dir
        .clone()
        .ok_or_else(|| crate::error::CoreError::Internal(format!("{context} missing target_dir")))
}

pub fn execute_task<F>(
    config: &SessionConfig,
    task: &TransferTask,
    cancelled: &AtomicBool,
    on_progress: F,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let connection = SftpConnection::connect(config)?;
    execute_task_with_connection(config, task, cancelled, on_progress, &connection)
}

pub fn execute_task_with_connection<F>(
    config: &SessionConfig,
    task: &TransferTask,
    cancelled: &AtomicBool,
    on_progress: F,
    connection: &SftpConnection,
) -> CoreResult<TaskExecutionOutput>
where
    F: FnMut(u64, Option<u64>) -> CoreResult<()>,
{
    let chunk_size = task.chunk_size_or(config.default_chunk_size());
    match task.kind {
        TaskKind::Upload => {
            let local_path = required_local_path(task, "upload task")?;
            let remote_path = required_remote_path(task, "upload task")?;
            transport::sftp::upload_file_with_connection(
                connection,
                &local_path,
                &remote_path,
                chunk_size,
                cancelled,
                on_progress,
            )
        }
        TaskKind::Download => {
            let local_path = required_local_path(task, "download task")?;
            let remote_path = required_remote_path(task, "download task")?;
            transport::sftp::download_file_with_connection(
                connection,
                &remote_path,
                &local_path,
                chunk_size,
                cancelled,
                on_progress,
            )
        }
        TaskKind::UploadBatch => {
            let target_dir = required_target_dir(task, "upload_batch task")?;
            transport::sftp::upload_batch(
                config,
                &task.local_paths,
                &target_dir,
                chunk_size,
                cancelled,
                on_progress,
            )
        }
        TaskKind::DownloadBatch => {
            let target_dir = required_target_dir(task, "download_batch task")?;
            transport::sftp::download_batch(
                config,
                &task.remote_paths,
                &target_dir,
                chunk_size,
                cancelled,
                on_progress,
            )
        }
        TaskKind::EnsureParentDirs => {
            let remote_path = required_remote_path(task, "ensure_parent_dirs task")?;
            transport::sftp::ensure_parent_dirs_with_connection(connection, &remote_path, cancelled)
        }
        TaskKind::ProbeRemoteFileSize => {
            let remote_path = required_remote_path(task, "probe_remote_file_size task")?;
            transport::sftp::probe_remote_file_size_with_connection(
                connection,
                &remote_path,
                cancelled,
            )
        }
    }
}
