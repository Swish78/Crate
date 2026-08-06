import Foundation
import Combine

struct StatDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

@MainActor
class ContainerDetailViewModel: ObservableObject {
    @Published var stats: ContainerAPI.Stats?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    
    @Published var cpuHistory: [StatDataPoint] = []
    @Published var memoryHistory: [StatDataPoint] = []
    
    let containerId: String
    private var refreshTimer: Timer?
    
    init(containerId: String) {
        self.containerId = containerId
    }
    
    func startFetchingStats() {
        fetchStats()
        // Poll for updates every 2 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchStats()
            }
        }
    }
    
    func stopFetchingStats() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func fetchStats() {
        if stats == nil {
            isLoading = true
        }
        
        Task {
            let result = ContainerAPI.getStats(containerId: containerId)
            
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(let fetchedStats):
                    self.stats = fetchedStats
                    self.errorMessage = nil
                    
                    let now = Date()
                    // Assuming cpuUsageUsec is in microseconds, let's keep it as Double milliseconds for charts
                    let cpuMs = Double(fetchedStats.cpuUsageUsec) / 1000.0
                    self.cpuHistory.append(StatDataPoint(timestamp: now, value: cpuMs))
                    
                    let memoryMB = Double(fetchedStats.memoryUsageBytes) / (1024.0 * 1024.0)
                    self.memoryHistory.append(StatDataPoint(timestamp: now, value: memoryMB))
                    
                    if self.cpuHistory.count > 20 {
                        self.cpuHistory.removeFirst()
                    }
                    if self.memoryHistory.count > 20 {
                        self.memoryHistory.removeFirst()
                    }
                    
                case .failure(let error):
                    // If we already have stats, maybe don't clear them on a transient error
                    if self.stats == nil {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
