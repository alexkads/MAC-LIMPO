import SwiftUI

struct CleaningProgressView: View {
    let category: CleaningCategory
    @Binding var isShowing: Bool
    let progress: Double
    let currentOperation: String
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Ícone animado
                ZStack {
                    Circle()
                        .fill(category.gradient)
                        .frame(width: 80, height: 80)
                        .shadow(color: category.color.opacity(0.5), radius: 20)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(progress > 0 ? 1.0 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).repeatForever(autoreverses: true), value: progress)
                
                // Título
                Text("Cleaning \(category.rawValue)")
                    .font(.system(size: 20, weight: .bold))
                
                // Operação atual
                Text(currentOperation)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 40)
                
                // Barra de progresso
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(category.gradient)
                                .frame(width: geometry.size.width * progress, height: 8)
                                .animation(.linear(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 8)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                // Botão cancelar
                Button("Cancel") {
                    isShowing = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .padding(.top, 8)
            }
            .padding(32)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 30)
            )
        }
    }
}
