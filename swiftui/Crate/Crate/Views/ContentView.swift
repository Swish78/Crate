import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContainerListViewModel()
    @State private var selectedContainerId: String?
    @State private var isShowingCreateSheet = false
    @State private var searchText = ""
    @State private var pendingDeleteId: String?

    private var filteredContainers: [ContainerAPI.Container] {
        guard !searchText.isEmpty else { return viewModel.containers }
        return viewModel.containers.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || ($0.image?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                if let error = viewModel.errorMessage, !viewModel.containers.isEmpty {
                    ErrorBanner(message: error) {
                        viewModel.errorMessage = nil
                    }
                }

                List(selection: $selectedContainerId) {
                    if viewModel.isLoading && viewModel.containers.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.containers.isEmpty {
                        if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    viewModel.fetchContainers()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "shippingbox.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                                    )
                                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)

                                Text("No Containers")
                                    .font(.headline)

                                Button(action: {
                                    isShowingCreateSheet = true
                                }) {
                                    Text("Create Container")
                                        .bold()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.large)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else if filteredContainers.isEmpty {
                        Text("No containers match \"\(searchText)\"")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredContainers) { container in
                            NavigationLink(value: container.id) {
                                ContainerRowView(container: container)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if container.status.lowercased() == "running" {
                                    Button {
                                        viewModel.stopContainer(id: container.id)
                                    } label: {
                                        Label("Stop", systemImage: "pause.fill")
                                    }
                                } else {
                                    Button {
                                        viewModel.startContainer(id: container.id)
                                    } label: {
                                        Label("Start", systemImage: "play.fill")
                                    }
                                }

                                Button(role: .destructive) {
                                    pendingDeleteId = container.id
                                } label: {
                                    Label("Delete Container", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search containers")
            }
            .navigationTitle("Crate")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isShowingCreateSheet = true
                    }) {
                        Label("Create Container", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: {
                        viewModel.fetchContainers()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .sheet(isPresented: $isShowingCreateSheet) {
                CreateContainerView(viewModel: viewModel, isPresented: $isShowingCreateSheet)
            }
            .alert(
                "Delete \"\(pendingDeleteId ?? "")\"?",
                isPresented: Binding(
                    get: { pendingDeleteId != nil },
                    set: { if !$0 { pendingDeleteId = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteId {
                        viewModel.deleteContainer(id: id)
                        if selectedContainerId == id {
                            selectedContainerId = nil
                        }
                    }
                }
            } message: {
                Text("This will permanently remove the container and its data. This action can't be undone.")
            }
        } detail: {
            // Detail Area
            if let selectedId = selectedContainerId,
               let container = viewModel.containers.first(where: { $0.id == selectedId }) {
                ContainerDetailView(
                    container: container,
                    onDelete: {
                        viewModel.deleteContainer(id: container.id)
                        selectedContainerId = nil
                    },
                    onStop: {
                        viewModel.stopContainer(id: container.id)
                    },
                    onStart: {
                        viewModel.startContainer(id: container.id)
                    }
                )
            } else {
                EmptySelectionView()
            }
        }
        .onAppear {
            viewModel.fetchContainers()
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.12))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

struct EmptySelectionView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Soft background blur circles
            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: -100, y: -100)
            
            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: 100, y: 100)
                
            VStack(spacing: 24) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                    .offset(y: isAnimating ? -10 : 10)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                
                VStack(spacing: 12) {
                    Text("Select a Container")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Choose a container from the sidebar to view its live statistics, charts, and detailed information.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
        }
    }
}
