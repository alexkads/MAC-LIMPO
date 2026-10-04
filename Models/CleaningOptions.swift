import Combine
import Foundation

/// Opções globais de limpeza compartilhadas entre a UI e os services.
///
/// O **modo agressivo** habilita a remoção de caches grandes porém regeneráveis
/// que ficam de fora por padrão por serem mais lentos de reconstruir — por
/// exemplo, os modelos de IA on-device do Chrome (`OptGuideOnDeviceModel`, ~4GB)
/// e `docker image prune -a`. Fica desligado por padrão; o usuário liga no popover.
final class CleaningOptions: ObservableObject, @unchecked Sendable {
    static let shared = CleaningOptions()

    @Published var aggressiveMode = false

    /// **Limpeza total do Docker**: para todos os contêineres e remove tudo —
    /// contêineres (e seus logs), imagens, volumes (bancos de dados inclusive),
    /// build cache e redes. Para máquinas de desenvolvimento em que tudo se
    /// recria com `docker compose up`; a decisão é do usuário. Desligada por
    /// padrão e sem persistência: volta a desligar a cada abertura do app, e a
    /// confirmação aparece mesmo com "não perguntar de novo".
    @Published var dockerFullCleanup = false

    private init() {}
}
