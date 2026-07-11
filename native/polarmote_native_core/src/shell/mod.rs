pub mod ffi;
pub mod data_object;
pub mod stream;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDragInfo {
    pub remote_path: String,
    pub display_name: String,
    pub size: u64,
    pub is_directory: bool,
}
