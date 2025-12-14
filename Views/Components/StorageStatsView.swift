import SwiftUI

struct StorageStatsView: View {
    let usedSpace: Int64
    let totalSpace: Int64
    
    private var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }
    
    private var freeSpace: Int64 {
        totalSpace - usedSpace
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Título
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Storage")
                    .font(.system(size: 18, weight: .bold))
                
                Spacer()
            }
            
            HStack(spacing: 20) {
                // Gráfico circular
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: usedPercentage)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                        Text("\(Int(usedPercentage * 100))%")
                            .font(.system(size: 18, weight: .bold))
                        Text("used")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Estatísticas
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(
                        label: "Used",
                        value: FileSystemHelper.shared.formatBytes(usedSpace),
                        color: .blue
                    )
                    
                    StatRow(
                        label: "Free",
                        value: FileSystemHelper.shared.formatBytes(freeSpace),
                        color: .green
                    )
                    
                    StatRow(
                        label: "Total",
                        value: FileSystemHelper.shared.formatBytes(totalSpace),
                        color: .gray
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor),
                            Color(NSColor.controlBackgroundColor).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}
