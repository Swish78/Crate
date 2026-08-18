import Foundation

/// Swift wrapper for the Rust container-client library to communicate directly with the macOS container-apiserver.
public struct ContainerAPI {
    
    /// Struct representing a container.
    public struct Container: Codable, Identifiable {
        public let id: String
        public let status: String
        public let image: String?
        public let startedDate: Double?
        public let ipv4Address: String?
    }
    
    /// Struct representing resource stats of a container.
    public struct Stats: Codable {
        public let id: String
        public let cpuUsageUsec: UInt64
        public let numProcesses: UInt64
        public let memoryUsageBytes: UInt64
        public let memoryLimitBytes: UInt64
        public let blockReadBytes: UInt64
        public let blockWriteBytes: UInt64
        public let networkRxBytes: UInt64
        public let networkTxBytes: UInt64
    }
    
    /// Error wrapper for Rust API errors.
    public enum APIError: Error, LocalizedError {
        case apiError(message: String)
        case decodingError
        case unknown
        
        public var errorDescription: String? {
            switch self {
            case .apiError(let message): return message
            case .decodingError: return "Failed to decode JSON from the Rust library"
            case .unknown: return "An unknown error occurred"
            }
        }
    }
    
    /// List all active and stopped containers.
    public static func listContainers() -> Result<[Container], APIError> {
        guard let rawStr = container_list_json() else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        // Check for error payload: {"error": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return .failure(.apiError(message: errorMsg))
        }
        
        do {
            let list = try JSONDecoder().decode([Container].self, from: data)
            return .success(list)
        } catch {
            return .failure(.decodingError)
        }
    }
    
    /// Get resource stats for a specific container by its ID.
    public static func getStats(containerId: String) -> Result<Stats, APIError> {
        guard let rawStr = container_stats_json(containerId) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        // Check for error payload: {"error": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return .failure(.apiError(message: errorMsg))
        }
        
        do {
            let stats = try JSONDecoder().decode(Stats.self, from: data)
            return .success(stats)
        } catch {
            return .failure(.decodingError)
        }
    }
    
    /// Delete a container by its ID.
    public static func delete(containerId: String, force: Bool = true) -> Result<Void, APIError> {
        guard let rawStr = container_delete(containerId, force) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return .failure(.apiError(message: errorMsg))
        }
        
        return .success(())
    }
    
    /// Create and run a new container using the given image name.
    public static func run(image: String) -> Result<String, APIError> {
        guard let rawStr = container_run(image) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMsg = json["error"] as? String {
                return .failure(.apiError(message: errorMsg))
            }
            if let id = json["id"] as? String {
                return .success(id)
            }
        }
        
        return .failure(.decodingError)
    }
    
    /// Stop a running container.
    public static func stop(containerId: String) -> Result<Void, APIError> {
        guard let rawStr = container_stop(containerId) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return .failure(.apiError(message: errorMsg))
        }
        
        return .success(())
    }
    
    /// File descriptors for a container's log streams.
    public struct LogFds {
        public let stdio: Int32
        public let boot: Int32
    }

    /// Obtain raw, ownership-transferred file descriptors for a container's
    /// `stdio` and `boot` log streams. Wrap each in a `FileHandle` and
    /// `close()` it when you're done reading.
    public static func getLogFds(containerId: String) -> Result<LogFds, APIError> {
        guard let rawStr = container_log_fds(containerId) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }

        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMsg = json["error"] as? String {
                return .failure(.apiError(message: errorMsg))
            }
            if let stdioFd = json["stdioFd"] as? Int, let bootFd = json["bootFd"] as? Int {
                return .success(LogFds(stdio: Int32(stdioFd), boot: Int32(bootFd)))
            }
        }

        return .failure(.decodingError)
    }

    /// Start a stopped container.
    public static func start(containerId: String) -> Result<Void, APIError> {
        guard let rawStr = container_start(containerId) else {
            return .failure(.unknown)
        }
        defer { container_free_string(rawStr) }
        
        let jsonStr = String(cString: rawStr)
        guard let data = jsonStr.data(using: .utf8) else {
            return .failure(.decodingError)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return .failure(.apiError(message: errorMsg))
        }
        
        return .success(())
    }
}
