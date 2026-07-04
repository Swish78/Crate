//! Error types for the container client.

use std::fmt;

/// Unified error type covering XPC transport, application-level, and
/// serialization failures.
#[derive(Debug)]
pub enum Error {
    /// Low-level XPC connection or protocol error.
    Xpc(String),

    /// Application-level error returned by container-apiserver.
    ///
    /// The server encodes these as JSON in the
    /// `com.apple.container.xpc.error` dictionary key.
    Api {
        code: String,
        message: String,
    },

    /// JSON serialization / deserialization failure.
    Json(serde_json::Error),

    /// OS I/O error (e.g. reading from a log file descriptor).
    Io(std::io::Error),
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Json(e) => Some(e),
            Self::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Xpc(msg) => write!(f, "xpc: {msg}"),
            Self::Api { code, message } => write!(f, "apiserver [{code}]: {message}"),
            Self::Json(e) => write!(f, "json: {e}"),
            Self::Io(e) => write!(f, "io: {e}"),
        }
    }
}

impl From<serde_json::Error> for Error {
    fn from(err: serde_json::Error) -> Self {
        Self::Json(err)
    }
}

impl From<std::io::Error> for Error {
    fn from(err: std::io::Error) -> Self {
        Self::Io(err)
    }
}
