import SwiftUI

struct ContainerRowView: View {
    let container: ContainerAPI.Container
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Indicator with glow
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.6), radius: isHovered ? 6 : 2, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(container.id)
                    .font(.headline)
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if let image = container.image {
                    Text(image)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                HStack(spacing: 8) {
                    if let ip = container.ipv4Address {
                        Text(ip)
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if let started = container.startedDate {
                        let date = Date(timeIntervalSinceReferenceDate: started)
                        let formatter = RelativeDateTimeFormatter()
                        Text(formatter.localizedString(for: date, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var statusColor: Color {
        // You can adjust these based on the actual status strings returned by the apiserver
        switch container.status.lowercased() {
        case "running":
            return .green
        case "stopped", "exited":
            return .red
        case "paused":
            return .orange
        default:
            return .gray
        }
    }
}
