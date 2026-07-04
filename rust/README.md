# container-client (Rust)

A high-performance, modern Rust client and C/Swift FFI wrapper for Apple's `container-apiserver` Mach service (`com.apple.container.apiserver`).

It bypasses the official `container` CLI entirely, communicating directly with the background launchd agent using Apple's XPC serialization protocol.

## Architecture

```text
┌─────────────────┐             XPC Msg            ┌────────────────────────┐
│  Swift / SwiftU │ ─────────────────────────────> │  container-apiserver    │
└─────────────────┘                                │  (com.apple.container.  │
        │                                          │   apiserver)            │
        ▼ (Calls C FFI)                            └────────────────────────┘
┌─────────────────┐                                            ▲
│   Rust Library  │ ───────────────────────────────────────────┘
│ (container_clie│             Raw System XPC Calls
└─────────────────┘
```

1. **Protocol Serialization**: The server utilizes standard XPC dictionaries (`xpc_dictionary_t`). The route selection key is `"com.apple.container.xpc.route"`.
2. **Data Serialization**: Parameters (such as list filters) and response bodies are JSON-encoded inside `xpc_data` blocks.
3. **Log FD Stream**: For logs, the server returns file descriptors (`xpc_fd_t`) inside an `xpc_array_t`. The client duplicates these via `xpc_fd_dup()` to perform native streaming.
4. **Rust 2024 Design**: Implements robust type wrappers around raw connection objects and dictionary references, utilizing RAII semantics to automatically release references and prevent memory leaks.

---

## Supported APIs

- **List Containers (`containerList`)** — Fetches metadata of all active/stopped containers.
- **Resource Stats (`containerStats`)** — Obtains live CPU, memory, PIDs, block I/O, and network usage.
- **Logs Streaming (`containerLogs`)** — Returns native file descriptors for both standard console (`stdio`) logs and Kata kernel (`boot`) logs.

---

## Folder Structure

- `src/ffi.rs` — Low-level standard `extern "C"` declarations for the Apple `libxpc` system library.
- `src/xpc.rs` — Memory-safe Rust wrappers (`XpcDict`, `Connection`) around the raw XPC handles implementing standard `Drop` lifetimes.
- `src/error.rs` — Unified error management covering transport, JSON serialization, and server-side errors.
- `src/routes.rs` — Serializable Rust structs representing the container models.
- `src/lib.rs` — High-level Rust APIs and C-compatible FFI entrypoints.

---

## Build Instructions

Compiling the library automatically generates both static/dynamic libraries and the C bridging header file (`container_client.h`) via `build.rs` and `cbindgen`.

### Requirements

- macOS (XPC is a macOS-only system API)
- Rust toolchain (Rust 1.85+ with 2024 edition support)

### Compiling

To build the library for development:

```bash
cargo build
```

To compile optimized libraries for release:

```bash
cargo build --release
```

This generates:

- `target/release/libcontainer_client.a` — Static library to link directly into Swift/Xcode.
- `target/release/libcontainer_client.dylib` — Dynamic library.
- `container_client.h` — The generated C bridging header containing the API definitions.

---

## Using the C / Swift FFI

To avoid complex ABI structure mappings between Swift and Rust, the FFI interfaces serialize models to JSON strings.

### The C Interface

The exported functions from [container_client.h](container_client.h) are:

```c
// Returns a JSON-formatted list of containers. Free return value when done.
char *container_list_json(void);

// Returns a JSON-formatted string of container statistics. Free return value when done.
char *container_stats_json(const char *container_id);

// Deallocates strings returned by this library.
void container_free_string(char *ptr);
```
