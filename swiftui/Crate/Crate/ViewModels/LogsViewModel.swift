import Foundation
import Combine
import Darwin

/// Streams a container's `stdio` log via a raw file descriptor obtained
/// from the Rust FFI layer (`container_log_fds`).
///
/// The `boot` (kernel) log descriptor is also returned by the FFI call but
/// isn't displayed here — it's closed immediately to avoid leaking it.
@MainActor
class LogsViewModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var errorMessage: String?
    @Published var isStreaming: Bool = false

    private let containerId: String
    private var stdioHandle: FileHandle?
    private var buffer = Data()
    private let maxLines = 2000

    init(containerId: String) {
        self.containerId = containerId
    }

    func startStreaming() {
        guard stdioHandle == nil else { return }
        errorMessage = nil
        lines.removeAll()
        buffer.removeAll()

        switch ContainerAPI.getLogFds(containerId: containerId) {
        case .success(let fds):
            close(fds.boot)

            let handle = FileHandle(fileDescriptor: fds.stdio, closeOnDealloc: true)
            stdioHandle = handle
            isStreaming = true

            handle.readabilityHandler = { [weak self] fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    // EOF: the writing end closed the pipe.
                    fh.readabilityHandler = nil
                    return
                }
                Task { @MainActor in
                    self?.appendChunk(chunk)
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func stopStreaming() {
        stdioHandle?.readabilityHandler = nil
        try? stdioHandle?.close()
        stdioHandle = nil
        isStreaming = false
    }

    private func appendChunk(_ chunk: Data) {
        buffer.append(chunk)

        var newLines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            newLines.append(String(data: lineData, encoding: .utf8) ?? "<invalid utf8>")
        }
        guard !newLines.isEmpty else { return }

        lines.append(contentsOf: newLines)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
