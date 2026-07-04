//! Rust client for Apple's `container-apiserver` XPC service.
//!
//! This crate lets you talk to the `com.apple.container.apiserver` Mach
//! service directly — the same service that backs the `container` CLI.
//!
//! # Architecture
//!
//! ```text
//! ┌──────────────┐  XPC   ┌────────────────────────┐
//! │  this crate  │───────▶│  container-apiserver    │
//! └──────────────┘        │  (com.apple.container.  │
//!                         │   apiserver)            │
//!                         └────────────────────────┘
//! ```
//!
//! Every request is a single XPC dictionary sent via
//! `xpc_connection_send_message_with_reply_sync`.  The route key
//! (`com.apple.container.xpc.route`) selects the operation; parameters
//! and responses are JSON-encoded `xpc_data` blobs.
//!
//! # C / Swift FFI
//!
//! The `extern "C"` functions at the bottom of this file return
//! heap-allocated JSON strings.  Call [`container_free_string`] to
//! release them.

pub mod error;
pub mod ffi;
pub mod routes;
pub mod xpc;

use error::Error;
use routes::{ContainerListFilters, ContainerSnapshot, ContainerStats};
use xpc::{Connection, XpcDict, ROUTE_KEY};

use std::ffi::{CStr, CString, c_char};
use std::fs::File;
use std::os::unix::io::FromRawFd;

/// Mach service name registered by `container system start`.
const SERVICE: &str = "com.apple.container.apiserver";

// ── Public Rust API ─────────────────────────────────────────────────────

/// List all containers, optionally filtered.
pub fn list_containers(
    filters: &ContainerListFilters,
) -> Result<Vec<ContainerSnapshot>, Error> {
    let conn = Connection::open(SERVICE)?;

    let msg = XpcDict::new();
    msg.set_string(ROUTE_KEY, "containerList");
    msg.set_data("listFilters", &serde_json::to_vec(filters)?);

    let reply = conn.send_sync(&msg)?;

    match reply.get_data("containers") {
        Some(bytes) => Ok(serde_json::from_slice(&bytes)?),
        None => Ok(Vec::new()),
    }
}

/// Fetch resource-usage statistics for a single container.
pub fn get_stats(container_id: &str) -> Result<ContainerStats, Error> {
    let conn = Connection::open(SERVICE)?;

    let msg = XpcDict::new();
    msg.set_string(ROUTE_KEY, "containerStats");
    msg.set_string("id", container_id);

    let reply = conn.send_sync(&msg)?;

    let bytes = reply
        .get_data("statistics")
        .ok_or_else(|| Error::Xpc("reply missing 'statistics' key".into()))?;

    Ok(serde_json::from_slice(&bytes)?)
}

/// Obtain the log file descriptors for a container.
///
/// Returns `(stdio, boot)` as owned [`File`] handles.  The server
/// passes these as `xpc_fd` values inside an `xpc_array`.
///
/// For streaming (`container logs -f`), simply keep reading from the
/// returned `File` — the descriptor stays open.
pub fn get_log_files(container_id: &str) -> Result<(File, File), Error> {
    let conn = Connection::open(SERVICE)?;

    let msg = XpcDict::new();
    msg.set_string(ROUTE_KEY, "containerLogs");
    msg.set_string("id", container_id);

    let reply = conn.send_sync(&msg)?;

    let logs_array = reply
        .get_raw_value("logs")
        .ok_or_else(|| Error::Xpc("reply missing 'logs' key".into()))?;

    let count = unsafe { ffi::xpc_array_get_count(logs_array) };
    if count < 2 {
        return Err(Error::Xpc(format!(
            "expected ≥ 2 log descriptors, got {count}"
        )));
    }

    let dup_fd = |index: usize| -> Result<File, Error> {
        let xpc_fd_obj = unsafe { ffi::xpc_array_get_value(logs_array, index) };
        let fd = unsafe { ffi::xpc_fd_dup(xpc_fd_obj) };
        if fd == -1 {
            return Err(Error::Xpc(format!(
                "xpc_fd_dup failed for log descriptor at index {index}"
            )));
        }
        Ok(unsafe { File::from_raw_fd(fd) })
    };

    let stdio = dup_fd(0)?;
    let boot = dup_fd(1)?;
    Ok((stdio, boot))
}

// ── C / Swift FFI ───────────────────────────────────────────────────────
//
// Convention: every function returns a `*mut c_char` pointing to a
// heap-allocated JSON string.  On success the JSON is the operation
// result; on failure it is `{"error": "…"}`.
//
// The caller **must** pass the pointer to `container_free_string` when
// done.

/// Returns a JSON array of containers.
///
/// # Safety
///
/// The returned pointer must be freed with [`container_free_string`].
#[unsafe(no_mangle)]
pub extern "C" fn container_list_json() -> *mut c_char {
    let filters = ContainerListFilters::default();
    match list_containers(&filters).and_then(|v| Ok(serde_json::to_string(&v)?)) {
        Ok(json) => cstring_into_raw(json),
        Err(e) => error_json(&e.to_string()),
    }
}

/// Returns a JSON object with container statistics.
///
/// # Safety
///
/// - `container_id` must be a valid, NUL-terminated C string.
/// - The returned pointer must be freed with [`container_free_string`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn container_stats_json(
    container_id: *const c_char,
) -> *mut c_char {
    let id = match unsafe { validate_c_str(container_id) } {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    match get_stats(id).and_then(|s| Ok(serde_json::to_string(&s)?)) {
        Ok(json) => cstring_into_raw(json),
        Err(e) => error_json(&e.to_string()),
    }
}

/// Free a string previously returned by this library.
///
/// # Safety
///
/// `ptr` must have been returned by one of the `container_*_json`
/// functions, or be null (in which case this is a no-op).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn container_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { CString::from_raw(ptr) });
    }
}

// ── FFI helpers ─────────────────────────────────────────────────────────

/// Validate and borrow a C string argument.  Returns an error JSON
/// pointer on failure so the caller can `return` it directly.
unsafe fn validate_c_str<'a>(ptr: *const c_char) -> Result<&'a str, *mut c_char> {
    if ptr.is_null() {
        return Err(error_json("argument is NULL"));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| error_json("argument is not valid UTF-8"))
}

fn cstring_into_raw(s: String) -> *mut c_char {
    // The only way this fails is if `s` contains an interior NUL, which
    // well-formed JSON never does.
    CString::new(s)
        .expect("JSON output contained interior NUL")
        .into_raw()
}

fn error_json(msg: &str) -> *mut c_char {
    let json = format!(r#"{{"error":"{msg}"}}"#);
    cstring_into_raw(json)
}
