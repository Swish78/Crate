import Foundation

/// Swift wrapper for the Rust container-client library to communicate directly with the macOS container-apiserver.
public struct ContainerAPI {
    
    /// Struct representing a container.
    public struct Container: Codable, Identifiable {
        public let id: String
        public let status: String
        public let image: String?
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
}
