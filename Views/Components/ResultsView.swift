import SwiftUI

struct ResultsView: View {
    let result: CleaningResult
    @Binding var isShowing: Bool
    
    @State private var animateSuccess = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Ícone de sucesso/erro
                ZStack {
                    Circle()
                        .fill(result.success ? Color.green : Color.red)
                        .frame(width: 80, height: 80)
                        .shadow(color: (result.success ? Color.green : Color.red).opacity(0.5), radius: 20)
                    
                    Image(systemName: result.success ? "checkmark" : "xmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(animateSuccess ? 1.0 : 0.5)
                .opacity(animateSuccess ? 1.0 : 0)
                
                // Título
                Text(result.success ? "Cleaning Complete!" : "Cleaning Failed")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(result.success ? .green : .red)
                
                // Estatísticas
                VStack(spacing: 16) {
                    StatisticRow(
                        icon: "arrow.down.circle.fill",
                        label: "Space Freed",
                        value: result.formattedSize,
                        color: .blue
                    )
                    
                    StatisticRow(
                        icon: "doc.fill",
                        label: "Files Removed",
                        value: "\(result.filesRemoved)",
                        color: .purple
                    )
                    
                    StatisticRow(
                        icon: "clock.fill",
                        label: "Time Taken",
                        value: String(format: "%.1fs", result.executionTime),
                        color: .orange
                    )
                }
                .padding(.horizontal, 20)
                
                // Erros (se houver)
                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Errors:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                        
                        ForEach(result.errors.prefix(3), id: \.self) { error in
                            Text("• \(error)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                
                // Botão fechar
                Button("Done") {
                    isShowing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 30)
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                animateSuccess = true
            }
        }
    }
}

struct StatisticRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
