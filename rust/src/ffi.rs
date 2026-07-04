//! Raw FFI bindings to Apple's `libxpc`.
//!
//! These mirror the public C API from `<xpc/xpc.h>`.  We only bind the
//! subset actually used by the container-apiserver protocol; adding more
//! is straightforward.
//!
//! # Safety
//!
//! Every function here is `unsafe` by definition.  The safe wrappers live
//! in [`crate::xpc`].

#![allow(non_camel_case_types)]

use std::ffi::{c_char, c_int, c_void};

// ── Opaque handle types ─────────────────────────────────────────────────

/// Opaque XPC object pointer (dictionaries, arrays, FDs, …).
pub type xpc_object_t = *mut c_void;

/// Opaque XPC connection handle.
pub type xpc_connection_t = *mut c_void;

/// Block/function-pointer type for `xpc_connection_set_event_handler`.
pub type XpcHandler = unsafe extern "C" fn(xpc_object_t);

// ── libxpc symbols ──────────────────────────────────────────────────────

unsafe extern "C" {
    // Type sentinel used to identify XPC error objects at runtime.
    pub static _xpc_type_error: c_void;

    // -- Connection lifecycle -------------------------------------------------

    pub fn xpc_connection_create_mach_service(
        name: *const c_char,
        target_queue: *mut c_void, // dispatch_queue_t, NULL → default
        flags: u64,
    ) -> xpc_connection_t;

    pub fn xpc_connection_set_event_handler(
        connection: xpc_connection_t,
        handler: XpcHandler,
    );

    pub fn xpc_connection_activate(connection: xpc_connection_t);
    pub fn xpc_connection_cancel(connection: xpc_connection_t);

    // -- Synchronous messaging ------------------------------------------------

    pub fn xpc_connection_send_message_with_reply_sync(
        connection: xpc_connection_t,
        message: xpc_object_t,
    ) -> xpc_object_t;

    // -- Dictionary -----------------------------------------------------------

    pub fn xpc_dictionary_create_empty() -> xpc_object_t;

    pub fn xpc_dictionary_set_string(
        xdict: xpc_object_t,
        key: *const c_char,
        value: *const c_char,
    );

    pub fn xpc_dictionary_set_data(
        xdict: xpc_object_t,
        key: *const c_char,
        bytes: *const c_void,
        length: libc::size_t,
    );

    pub fn xpc_dictionary_get_string(
        xdict: xpc_object_t,
        key: *const c_char,
    ) -> *const c_char;

    pub fn xpc_dictionary_get_data(
        xdict: xpc_object_t,
        key: *const c_char,
        length: *mut libc::size_t,
    ) -> *const c_void;

    pub fn xpc_dictionary_get_value(
        xdict: xpc_object_t,
        key: *const c_char,
    ) -> xpc_object_t;

    // -- Array ----------------------------------------------------------------

    pub fn xpc_array_get_count(xarray: xpc_object_t) -> libc::size_t;
    pub fn xpc_array_get_value(xarray: xpc_object_t, index: libc::size_t) -> xpc_object_t;

    // -- File descriptors -----------------------------------------------------

    pub fn xpc_fd_dup(xpc_fd: xpc_object_t) -> c_int;

    // -- Introspection --------------------------------------------------------

    /// Returns a malloc'd C string; **caller must `free()` it**.
    pub fn xpc_copy_description(object: xpc_object_t) -> *mut c_char;
    pub fn xpc_get_type(object: xpc_object_t) -> *const c_void;

    // -- Reference counting ---------------------------------------------------

    pub fn xpc_release(object: xpc_object_t);
}
