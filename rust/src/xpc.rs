//! Safe wrappers around the raw libxpc FFI.
//!
//! The two main types are:
//!
//! - [`XpcDict`] — an owned XPC dictionary (the wire message format).
//! - [`Connection`] — an active connection to a Mach service.
//!
//! Both implement `Drop` to release XPC resources deterministically.

use crate::error::Error;
use crate::ffi;
use crate::routes::ApiErrorPayload;

use std::ffi::{c_void, CStr, CString};
use std::ptr;

// ── Protocol constants ──────────────────────────────────────────────────

/// XPC dictionary key identifying the requested operation.
/// From `XPCMessage.routeKey` in the Swift source.
pub(crate) const ROUTE_KEY: &str = "com.apple.container.xpc.route";

/// XPC dictionary key carrying a JSON-encoded error on failure.
/// From `XPCMessage.errorKey` in the Swift source.
const ERROR_KEY: &str = "com.apple.container.xpc.error";

// ── XpcDict ─────────────────────────────────────────────────────────────

/// An owned XPC dictionary.
///
/// Wraps a raw `xpc_object_t` with RAII semantics — the underlying
/// object is released on drop.
pub struct XpcDict {
    ptr: ffi::xpc_object_t,
    /// If `true`, this wrapper owns the pointer and will `xpc_release` it.
    /// Borrowed views (e.g. from `xpc_dictionary_get_value`) set this to `false`.
    owned: bool,
}

impl XpcDict {
    /// Create a new, empty XPC dictionary.
    #[must_use]
    pub fn new() -> Self {
        let ptr = unsafe { ffi::xpc_dictionary_create_empty() };
        assert!(!ptr.is_null(), "xpc_dictionary_create_empty returned NULL");
        Self { ptr, owned: true }
    }

    /// Wrap an existing owned pointer.
    ///
    /// # Panics
    ///
    /// Panics if `ptr` is null.
    pub(crate) fn from_owned(ptr: ffi::xpc_object_t) -> Self {
        assert!(!ptr.is_null());
        Self { ptr, owned: true }
    }

    // ── Setters ─────────────────────────────────────────────────────────

    pub fn set_string(&self, key: &str, value: &str) {
        let c_key = CString::new(key).expect("key contains interior NUL");
        let c_val = CString::new(value).expect("value contains interior NUL");
        unsafe {
            ffi::xpc_dictionary_set_string(self.ptr, c_key.as_ptr(), c_val.as_ptr());
        }
    }

    pub fn set_data(&self, key: &str, bytes: &[u8]) {
        let c_key = CString::new(key).expect("key contains interior NUL");
        unsafe {
            ffi::xpc_dictionary_set_data(
                self.ptr,
                c_key.as_ptr(),
                bytes.as_ptr().cast::<c_void>(),
                bytes.len(),
            );
        }
    }

    // ── Getters ─────────────────────────────────────────────────────────

    pub fn get_string(&self, key: &str) -> Option<String> {
        let c_key = CString::new(key).ok()?;
        unsafe {
            let raw = ffi::xpc_dictionary_get_string(self.ptr, c_key.as_ptr());
            if raw.is_null() {
                return None;
            }
            Some(CStr::from_ptr(raw).to_string_lossy().into_owned())
        }
    }

    /// Copy the raw bytes of an `xpc_data` value out of the dictionary.
    pub fn get_data(&self, key: &str) -> Option<Vec<u8>> {
        let c_key = CString::new(key).ok()?;
        let mut len: libc::size_t = 0;
        unsafe {
            let raw = ffi::xpc_dictionary_get_data(self.ptr, c_key.as_ptr(), &mut len);
            if raw.is_null() || len == 0 {
                return None;
            }
            Some(std::slice::from_raw_parts(raw.cast::<u8>(), len).to_vec())
        }
    }

    /// Get a nested XPC value by key.  Returns the **raw** pointer
    /// because the caller may need to interpret it as an array or FD.
    pub fn get_raw_value(&self, key: &str) -> Option<ffi::xpc_object_t> {
        let c_key = CString::new(key).ok()?;
        let raw = unsafe { ffi::xpc_dictionary_get_value(self.ptr, c_key.as_ptr()) };
        if raw.is_null() { None } else { Some(raw) }
    }

    // ── Introspection ───────────────────────────────────────────────────

    /// Check whether this object is an XPC-level error sentinel.
    fn is_error(&self) -> bool {
        unsafe {
            let t = ffi::xpc_get_type(self.ptr);
            t == std::ptr::addr_of!(ffi::_xpc_type_error).cast()
        }
    }

    /// Human-readable dump of the XPC object (useful for debugging).
    ///
    /// The returned string is allocated by libxpc and freed here.
    #[must_use]
    pub fn description(&self) -> String {
        unsafe {
            let raw = ffi::xpc_copy_description(self.ptr);
            if raw.is_null() {
                return String::from("<null>");
            }
            let desc = CStr::from_ptr(raw).to_string_lossy().into_owned();
            libc::free(raw.cast::<c_void>());
            desc
        }
    }

    pub(crate) fn as_ptr(&self) -> ffi::xpc_object_t {
        self.ptr
    }
}

impl Drop for XpcDict {
    fn drop(&mut self) {
        if self.owned && !self.ptr.is_null() {
            unsafe { ffi::xpc_release(self.ptr) };
        }
    }
}

// ── Connection ──────────────────────────────────────────────────────────

/// An active XPC connection to a Mach service.
///
/// Connections are cancelled and released on drop.
pub struct Connection {
    ptr: ffi::xpc_connection_t,
}

/// No-op event handler required by XPC before `xpc_connection_activate`.
///
/// We use an `extern "C" fn` instead of a block to avoid pulling in
/// block-runtime dependencies.  The apiserver protocol never sends
/// unsolicited events, so this handler is never meaningfully invoked.
unsafe extern "C" fn noop_event_handler(_event: ffi::xpc_object_t) {}

impl Connection {
    /// Connect to the named Mach service.
    ///
    /// This creates the connection, installs a no-op event handler (required
    /// by `xpc_connection_activate`), and activates it.
    pub fn open(service: &str) -> Result<Self, Error> {
        let c_name = CString::new(service).map_err(|_| {
            Error::Xpc(format!("service name contains interior NUL: {service:?}"))
        })?;

        let ptr = unsafe {
            ffi::xpc_connection_create_mach_service(c_name.as_ptr(), ptr::null_mut(), 0)
        };
        if ptr.is_null() {
            return Err(Error::Xpc("xpc_connection_create_mach_service returned NULL".into()));
        }

        unsafe {
            ffi::xpc_connection_set_event_handler(ptr, noop_event_handler);
            ffi::xpc_connection_activate(ptr);
        }

        Ok(Self { ptr })
    }

    /// Send a message and block until the server replies.
    ///
    /// Checks for both XPC-level errors (connection died) and
    /// application-level errors (the `com.apple.container.xpc.error` key).
    pub fn send_sync(&self, message: &XpcDict) -> Result<XpcDict, Error> {
        let reply_ptr = unsafe {
            ffi::xpc_connection_send_message_with_reply_sync(self.ptr, message.as_ptr())
        };
        if reply_ptr.is_null() {
            return Err(Error::Xpc("received NULL reply".into()));
        }

        let reply = XpcDict::from_owned(reply_ptr);

        // XPC-level error (connection interrupted / invalid, etc.)
        if reply.is_error() {
            let desc = reply
                .get_string("XPCErrorDescription")
                .unwrap_or_else(|| String::from("unknown XPC error"));
            return Err(Error::Xpc(desc));
        }

        // Application-level error from container-apiserver
        if let Some(err_bytes) = reply.get_data(ERROR_KEY) {
            if let Ok(payload) = serde_json::from_slice::<ApiErrorPayload>(&err_bytes) {
                return Err(Error::Api {
                    code: payload.code,
                    message: payload.message,
                });
            }
        }

        Ok(reply)
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe {
                ffi::xpc_connection_cancel(self.ptr);
                // xpc_connection objects are reference-counted just like
                // other xpc_object_t values.
                ffi::xpc_release(self.ptr);
            }
        }
    }
}
