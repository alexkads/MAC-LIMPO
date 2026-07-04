import Combine
import Foundation

/// Opções globais de limpeza compartilhadas entre a UI e os services.
///
/// O **modo agressivo** habilita a remoção de caches grandes porém regeneráveis
/// que ficam de fora por padrão por serem mais lentos de reconstruir — por
/// exemplo, os modelos de IA on-device do Chrome (`OptGuideOnDeviceModel`, ~4GB)
/// e `docker image prune -a`. Fica desligado por padrão; o usuário liga no popover.
final class CleaningOptions: ObservableObject {
    static let shared = CleaningOptions()

    @Published var aggressiveMode = false

    private init() {}
}
