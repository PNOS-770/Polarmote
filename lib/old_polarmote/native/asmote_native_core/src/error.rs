use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("invalid utf8 input")]
    InvalidUtf8,
    #[error("invalid json: {0}")]
    InvalidJson(String),
    #[error("session not found: {0}")]
    SessionNotFound(u64),
    #[error("authentication failed")]
    AuthenticationFailed,
    #[error("task cancelled")]
    Cancelled,
    #[error("io error: {0}")]
    Io(String),
    #[error("ssh error: {0}")]
    Ssh(String),
    #[error("internal error: {0}")]
    Internal(String),
}

pub type CoreResult<T> = Result<T, CoreError>;

impl From<std::io::Error> for CoreError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value.to_string())
    }
}

impl From<libssh_rs::Error> for CoreError {
    fn from(value: libssh_rs::Error) -> Self {
        Self::Ssh(value.to_string())
    }
}

impl From<serde_json::Error> for CoreError {
    fn from(value: serde_json::Error) -> Self {
        Self::InvalidJson(value.to_string())
    }
}
