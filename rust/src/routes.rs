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
#[derive(Serialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ContainerSnapshot {
    pub id: String,
    pub status: String,
    pub image: Option<String>,
    pub started_date: Option<f64>,
    pub ipv4_address: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

impl<'de> Deserialize<'de> for ContainerSnapshot {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct RawSnapshot {
            status: String,
            configuration: RawConfig,
            started_date: Option<f64>,
            networks: Option<Vec<RawNetwork>>,
            #[serde(flatten)]
            extra: HashMap<String, serde_json::Value>,
        }
        
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct RawConfig {
            id: String,
            image: Option<RawImage>,
        }
        
        #[derive(Deserialize, Default)]
        #[serde(rename_all = "camelCase")]
        struct RawImage {
            reference: String,
        }
        
        #[derive(Deserialize, Default)]
        #[serde(rename_all = "camelCase")]
        struct RawNetwork {
            ipv4_address: Option<String>,
        }
        
        let raw = RawSnapshot::deserialize(deserializer)?;
        let ip = raw.networks
            .and_then(|nets| nets.into_iter().next())
            .and_then(|net| net.ipv4_address);
            
        Ok(ContainerSnapshot {
            id: raw.configuration.id,
            status: raw.status,
            image: raw.configuration.image.map(|i| i.reference),
            started_date: raw.started_date,
            ipv4_address: ip,
            extra: raw.extra,
        })
    }
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
