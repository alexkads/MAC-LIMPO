import Foundation

/// Limpa o cache global de pacotes do NuGet (.NET). O diretório `packages` é um
/// cache de restore — é recriado automaticamente no próximo `dotnet restore`/build.
final class NuGetCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .nugetCache, targets: [
            CleanTarget("~/.nuget/packages", label: "NuGet packages"),
            CleanTarget("~/.nuget/v3-cache", label: "NuGet v3 cache"),
            CleanTarget("~/.nuget/plugins-cache", label: "NuGet plugins cache"),
            CleanTarget("~/.local/share/NuGet/http-cache", label: "NuGet http cache")
        ])
    }
}
