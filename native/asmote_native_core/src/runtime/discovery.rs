use crate::error::{CoreError, CoreResult};
use crate::models_v2::{
    GraphId, GraphMetadata, NodeId, NodeOperation, QosLevel, TransferGraph, TransferNode,
};
use crate::runtime::provider::TransportProvider;
use std::fs;
use std::path::{Path, PathBuf};

pub struct DiscoveryPipeline;

impl DiscoveryPipeline {
    pub fn build_upload_graph(
        local_paths: &[String],
        target_dir: &str,
        qos: QosLevel,
    ) -> CoreResult<TransferGraph> {
        let mut graph = TransferGraph {
            graph_id: Some(GraphId(0)),
            name: Some("upload_graph".to_string()),
            nodes: Vec::new(),
            metadata: GraphMetadata {
                source_root: None,
                target_root: Some(target_dir.to_string()),
                total_files: Some(0),
                total_dirs: Some(0),
            },
        };

        let mut next_id = 1u64;

        for item in local_paths {
            let path = PathBuf::from(item);
            if !path.exists() {
                return Err(CoreError::Io(format!("local path not found: {item}")));
            }
            Self::scan_local_path(&path, &path, target_dir, qos, &mut graph, &mut next_id)?;
        }

        Ok(graph)
    }

    pub fn build_download_graph<P: TransportProvider>(
        provider: &P,
        remote_paths: &[String],
        target_dir: &str,
        qos: QosLevel,
    ) -> CoreResult<TransferGraph> {
        let mut graph = TransferGraph {
            graph_id: Some(GraphId(0)),
            name: Some("download_graph".to_string()),
            nodes: Vec::new(),
            metadata: GraphMetadata {
                source_root: None,
                target_root: Some(target_dir.to_string()),
                total_files: Some(0),
                total_dirs: Some(0),
            },
        };

        let mut next_id = 1u64;
        for remote in remote_paths {
            Self::scan_remote_path(
                provider,
                remote,
                remote,
                target_dir,
                qos,
                &mut graph,
                &mut next_id,
            )?;
        }

        Ok(graph)
    }

    fn scan_local_path(
        base: &Path,
        current: &Path,
        target_dir: &str,
        qos: QosLevel,
        graph: &mut TransferGraph,
        next_id: &mut u64,
    ) -> CoreResult<()> {
        let metadata = fs::metadata(current)?;
        if metadata.is_dir() {
            let relative = current
                .strip_prefix(base.parent().unwrap_or(base))
                .unwrap_or(current)
                .to_string_lossy()
                .replace('\\', "/");
            if !relative.is_empty() {
                graph.nodes.push(TransferNode {
                    node_id: NodeId(*next_id),
                    operation: NodeOperation::MkdirRemote {
                        path: format!("{}/{}", target_dir.trim_end_matches('/'), relative),
                        mode: Some(0o755),
                    },
                    depends_on: Vec::new(),
                    qos: Some(qos),
                    priority: Some(5),
                    retry_policy: None,
                    estimated_bytes: None,
                    display_name: Some(relative),
                });
                *next_id += 1;
                graph.metadata.total_dirs = Some(graph.metadata.total_dirs.unwrap_or(0) + 1);
            }

            let mut children: Vec<PathBuf> = fs::read_dir(current)?
                .filter_map(|entry| entry.ok().map(|item| item.path()))
                .collect();
            children.sort();

            for child in children {
                Self::scan_local_path(base, &child, target_dir, qos, graph, next_id)?;
            }
            return Ok(());
        }

        let relative = current
            .strip_prefix(base.parent().unwrap_or(base))
            .unwrap_or(current)
            .to_string_lossy()
            .replace('\\', "/");

        let remote = format!("{}/{}", target_dir.trim_end_matches('/'), relative);
        graph.nodes.push(TransferNode {
            node_id: NodeId(*next_id),
            operation: NodeOperation::UploadFile {
                local_path: current.to_string_lossy().to_string(),
                remote_path: remote,
                chunk_size: None,
            },
            depends_on: Vec::new(),
            qos: Some(qos),
            priority: Some(5),
            retry_policy: None,
            estimated_bytes: Some(metadata.len()),
            display_name: Some(relative),
        });
        *next_id += 1;
        graph.metadata.total_files = Some(graph.metadata.total_files.unwrap_or(0) + 1);
        Ok(())
    }

    fn scan_remote_path<P: TransportProvider>(
        provider: &P,
        base: &str,
        current: &str,
        target_dir: &str,
        qos: QosLevel,
        graph: &mut TransferGraph,
        next_id: &mut u64,
    ) -> CoreResult<()> {
        let meta = provider
            .stat_remote(current)?
            .ok_or_else(|| CoreError::Io(format!("remote path not found: {current}")))?;

        if meta.is_dir {
            let relative = current
                .strip_prefix(base)
                .unwrap_or(current)
                .trim_start_matches('/')
                .to_string();
            if !relative.is_empty() {
                graph.nodes.push(TransferNode {
                    node_id: NodeId(*next_id),
                    operation: NodeOperation::MkdirLocal {
                        path: format!("{}/{}", target_dir.trim_end_matches('/'), relative),
                    },
                    depends_on: Vec::new(),
                    qos: Some(qos),
                    priority: Some(5),
                    retry_policy: None,
                    estimated_bytes: None,
                    display_name: Some(relative),
                });
                *next_id += 1;
                graph.metadata.total_dirs = Some(graph.metadata.total_dirs.unwrap_or(0) + 1);
            }

            for child in provider.list_remote(current)? {
                Self::scan_remote_path(
                    provider,
                    base,
                    &child.path,
                    target_dir,
                    qos,
                    graph,
                    next_id,
                )?;
            }
            return Ok(());
        }

        let relative = current
            .strip_prefix(base)
            .unwrap_or(current)
            .trim_start_matches('/')
            .to_string();

        graph.nodes.push(TransferNode {
            node_id: NodeId(*next_id),
            operation: NodeOperation::DownloadFile {
                remote_path: current.to_string(),
                local_path: format!("{}/{}", target_dir.trim_end_matches('/'), relative),
                chunk_size: None,
            },
            depends_on: Vec::new(),
            qos: Some(qos),
            priority: Some(5),
            retry_policy: None,
            estimated_bytes: Some(meta.size),
            display_name: Some(relative),
        });
        *next_id += 1;
        graph.metadata.total_files = Some(graph.metadata.total_files.unwrap_or(0) + 1);
        Ok(())
    }
}
