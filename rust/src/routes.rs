//! JSON-serialisable models matching the container-apiserver protocol.
//!
//! Field names use `#[serde(rename_all = "camelCase")]` because the
//! server encodes everything as camelCase JSON inside `xpc_data` blobs.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── Containers ──────────────────────────────────────────────────────────

/// Mirrors `ContainerSnapshot` from the Swift source.
///
/// We intentionally use `#[serde(deny_unknown_fields)]` **off** here so
/// the crate keeps working if the server adds new fields.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ContainerSnapshot {
    pub id: String,
    pub status: String,
    #[serde(default)]
    pub image: String,
    /// Additional fields are captured here so nothing is silently lost.
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

/// Filters sent with `containerList`.
///
/// An empty `ContainerListFilters` (the `Default` impl) matches all
/// containers — identical to `ContainerListFilters.all` in Swift.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct ContainerListFilters {
    #[serde(default)]
    pub ids: Vec<String>,
    #[serde(default)]
    pub labels: HashMap<String, String>,
}

// ── Stats ───────────────────────────────────────────────────────────────

/// Mirrors `ContainerStats` from the Swift source.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ContainerStats {
    pub id: String,
    pub cpu_usage_usec: u64,
    pub num_processes: u64,
    pub memory_usage_bytes: u64,
    pub memory_limit_bytes: u64,
    pub block_read_bytes: u64,
    pub block_write_bytes: u64,
    pub network_rx_bytes: u64,
    pub network_tx_bytes: u64,
}

// ── Errors ──────────────────────────────────────────────────────────────

/// JSON payload inside `com.apple.container.xpc.error`.
#[derive(Deserialize, Debug)]
pub(crate) struct ApiErrorPayload {
    pub code: String,
    pub message: String,
}
