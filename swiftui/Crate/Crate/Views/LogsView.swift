import SwiftUI

struct LogsView: View {
    @ObservedObject var viewModel: LogsViewModel
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.lines.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for log output…")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .onChange(of: viewModel.lines.count) {
                        guard autoScroll, let lastIndex = viewModel.lines.indices.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
            }
        }
    }
}
