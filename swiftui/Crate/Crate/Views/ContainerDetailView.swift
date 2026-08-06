import SwiftUI
import Charts

struct ContainerDetailView: View {
    @StateObject private var viewModel: ContainerDetailViewModel
    @StateObject private var logsViewModel: LogsViewModel
    let container: ContainerAPI.Container
    var onDelete: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil

    @State private var selectedTab: Tab = .overview
    @State private var isShowingDeleteConfirmation = false

    enum Tab {
        case overview, logs
    }

    init(container: ContainerAPI.Container, onDelete: (() -> Void)? = nil, onStop: (() -> Void)? = nil, onStart: (() -> Void)? = nil) {
        self.container = container
        self.onDelete = onDelete
        self.onStop = onStop
        self.onStart = onStart
        self._viewModel = StateObject(wrappedValue: ContainerDetailViewModel(containerId: container.id))
        self._logsViewModel = StateObject(wrappedValue: LogsViewModel(containerId: container.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(Tab.overview)
                Text("Logs").tag(Tab.logs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            switch selectedTab {
            case .overview:
                overviewTab
            case .logs:
                LogsView(viewModel: logsViewModel)
                    .onAppear { logsViewModel.startStreaming() }
                    .onDisappear { logsViewModel.stopStreaming() }
            }
        }
        .navigationTitle(container.id)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if container.status.lowercased() == "running" {
                    Button(action: {
                        onStop?()
                    }) {
                        Label("Stop", systemImage: "pause.fill")
                    }
                    .tint(.orange)
                } else {
                    Button(action: {
                        onStart?()
                    }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .tint(.green)
                }

                Button(role: .destructive, action: {
                    isShowingDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .alert("Delete \"\(container.id)\"?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This will permanently remove the container and its data. This action can't be undone.")
        }
        .onAppear {
            viewModel.startFetchingStats()
        }
        .onDisappear {
            viewModel.stopFetchingStats()
        }
    }

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.id)
                            .font(.largeTitle)
                            .bold()
                        
                        if let image = container.image {
                            Text(image)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            if let ip = container.ipv4Address {
                                Label(ip, systemImage: "network")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            if let started = container.startedDate {
                                let date = Date(timeIntervalSinceReferenceDate: started)
                                let formatter = RelativeDateTimeFormatter()
                                Label(formatter.localizedString(for: date, relativeTo: Date()), systemImage: "clock")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 10)
                
                // Status Pill
                Text(container.status.uppercased())
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
                
                Divider()
                
                if viewModel.isLoading && viewModel.stats == nil {
                    ProgressView("Fetching Stats...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = viewModel.errorMessage, viewModel.stats == nil {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.largeTitle)
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if let stats = viewModel.stats {
                    
                    // Charts Section
                    if !viewModel.cpuHistory.isEmpty || !viewModel.memoryHistory.isEmpty {
                        HStack(spacing: 16) {
                            ChartCard(title: "CPU Usage (ms)", data: viewModel.cpuHistory, color: .blue)
                            ChartCard(title: "Memory (MB)", data: viewModel.memoryHistory, color: .green)
                        }
                        .frame(height: 200)
                        .padding(.bottom, 16)
                    }
                    
                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(title: "CPU Usage", value: "\(stats.cpuUsageUsec / 1000) ms", icon: "cpu", color: .blue)
                        StatCard(title: "Processes", value: "\(stats.numProcesses)", icon: "terminal", color: .purple)
                        StatCard(title: "Memory", value: formatBytes(stats.memoryUsageBytes), icon: "memorychip", color: .green)
                        StatCard(title: "Memory Limit", value: formatBytes(stats.memoryLimitBytes), icon: "memorychip.fill", color: .mint)
                        StatCard(title: "Network Rx", value: formatBytes(stats.networkRxBytes), icon: "arrow.down.circle", color: .orange)
                        StatCard(title: "Network Tx", value: formatBytes(stats.networkTxBytes), icon: "arrow.up.circle", color: .orange)
                        StatCard(title: "Block Read", value: formatBytes(stats.blockReadBytes), icon: "externaldrive", color: .indigo)
                        StatCard(title: "Block Write", value: formatBytes(stats.blockWriteBytes), icon: "externaldrive.fill", color: .indigo)
                    }
                } else {
                    Text("No stats available.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
                
                Spacer()
            }
            .padding(24)
        }
    }

    private var statusColor: Color {
        switch container.status.lowercased() {
        case "running": return .green
        case "stopped", "exited": return .red
        case "paused": return .orange
        default: return .gray
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct ChartCard: View {
    let title: String
    let data: [StatDataPoint]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            
            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.4), color.opacity(0.0)]),
                    startPoint: .top,
                    endPoint: .bottom
                ))
                
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis(.hidden)
            .animation(.easeInOut, value: data.count)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3)
                    .bold()
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        .animation(.default, value: value)
    }
}
