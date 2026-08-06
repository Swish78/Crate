import Foundation
import Combine

@MainActor
class ContainerListViewModel: ObservableObject {
    @Published var containers: [ContainerAPI.Container] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    
    func fetchContainers() {
        isLoading = true
        errorMessage = nil
        
        // We use a background task to avoid blocking the main thread if XPC is slow
        Task {
            let result = ContainerAPI.listContainers()
            
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(let list):
                    self.containers = list
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func createContainer(image: String) {
        isLoading = true
        Task {
            let result = ContainerAPI.run(image: image)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(_):
                    self.fetchContainers()
                case .failure(let error):
                    self.errorMessage = "Failed to create container: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func deleteContainer(id: String) {
        isLoading = true
        Task {
            let result = ContainerAPI.delete(containerId: id)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success():
                    self.fetchContainers()
                case .failure(let error):
                    self.errorMessage = "Failed to delete container: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func stopContainer(id: String) {
        isLoading = true
        Task {
            let result = ContainerAPI.stop(containerId: id)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success():
                    self.fetchContainers()
                case .failure(let error):
                    self.errorMessage = "Failed to stop container: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startContainer(id: String) {
        isLoading = true
        Task {
            let result = ContainerAPI.start(containerId: id)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success():
                    self.fetchContainers()
                case .failure(let error):
                    self.errorMessage = "Failed to start container: \(error.localizedDescription)"
                }
            }
        }
    }
}
