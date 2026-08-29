import Foundation

/// Limpa os caches do Expo CLI em ~/.expo: apps Expo Go baixados, APKs,
/// apps de simulador iOS e caches de template/schema. Tudo é re-baixado
/// sob demanda pelo próprio CLI.
final class ExpoCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .expoCache, targets: [
            CleanTarget("~/.expo/expo-go", label: "Expo Go downloads", strategy: .removeContents),
            CleanTarget("~/.expo/android-apk-cache", label: "Android APK cache", strategy: .removeContents),
            CleanTarget("~/.expo/ios-simulator-app-cache", label: "iOS simulator app cache", strategy: .removeContents),
            CleanTarget("~/.expo/cache", label: "Expo cache", strategy: .removeContents),
            CleanTarget("~/.expo/native-modules-cache", label: "Native modules cache", strategy: .removeContents),
            CleanTarget("~/.expo/template-cache", label: "Template cache", strategy: .removeContents),
            CleanTarget("~/.expo/versions-cache", label: "Versions cache", strategy: .removeContents),
            CleanTarget("~/.expo/schema-cache", label: "Schema cache", strategy: .removeContents)
        ])
    }
}
