# Como Criar o Projeto no Xcode

O projeto usa Swift Package Manager e não mantém um `.xcodeproj` versionado. No Xcode 27, abra diretamente o `Package.swift`.

## Passos para Configurar no Xcode

### 1. Abrir o Xcode
- Abra o Xcode da pasta Applications

### 2. Abrir o pacote
- File > Open...
- Selecione `Package.swift` na raiz do repositório
- Escolha o produto executável `MAC-LIMPO`

### 3. Conferir a configuração
Preencha os campos:
- **Product Name**: `MAC-LIMPO`
- **Deployment target**: macOS `27.0`
- **Swift tools**: `6.4`
- **Arquitetura de distribuição**: `arm64`
- O target já inclui Foundation Models e App Intents por meio dos imports do pacote.

### 4. Arquivos do pacote

Não adicione os arquivos manualmente. O `Package.swift` lista explicitamente todas as fontes, incluindo `Intents/`, `Services/AppleIntelligenceService.swift` e `Views/Components/AppleIntelligenceInsightView.swift`.

### 5. Configurar Info.plist

1. No Project Navigator, selecione o projeto (ícone azul no topo)
2. Selecione o Target "MAC-LIMPO"
3. Aba "Info"
4. Na seção "Custom macOS Application Target Properties":
   - Clique no + e adicione:
     - Key: `LSUIElement`
     - Type: `Boolean`
     - Value: `YES`

### 6. Configurar Deployment Target

1. Na aba "General"
2. Em "Minimum Deployments"
3. Defina "macOS" para `27.0` — o projeto não oferece suporte a versões anteriores

### 7. Build e Executar

1. Selecione "My Mac" como destination
2. Pressione ⌘R (ou Product > Run)
3. A aplicação será compilada e executada
4. Procure o ícone de lixeira no menu bar (canto superior direito)

## Estrutura de Arquivos Esperada

```
MAC-LIMPO/
├── Package.swift
├── MACLIMPOApp.swift
├── Info.plist
├── Assets.xcassets/
├── Models/
│   ├── CleaningCategory.swift
│   └── CleaningResult.swift
├── Services/
│   ├── CleaningService.swift
│   ├── CleaningServiceRegistry.swift
│   ├── AppleIntelligenceService.swift
│   ├── DockerCleaningService.swift
│   ├── DevPackagesCleaningService.swift
│   ├── TempFilesCleaningService.swift
│   ├── LogsCleaningService.swift
│   └── AppCacheCleaningService.swift
├── Views/
│   ├── MenuBarView.swift
│   └── Components/
│       ├── AppleIntelligenceInsightView.swift
│       ├── CleaningCategoryCard.swift
│       ├── StorageStatsView.swift
│       ├── CleaningProgressView.swift
│       └── ResultsView.swift
├── Utilities/
│   ├── FileSystemHelper.swift
│   └── ShellExecutor.swift
├── Intents/
│   └── MACLIMPOIntents.swift
└── README.md
```

## Troubleshooting

### Se houver erros de compilação:

1. **Imports faltando**: Adicione `import SwiftUI` e `import Foundation` onde necessário
2. **Arquivos não encontrados**: Verifique se todos os .swift estão adicionados ao Target
3. **LSUIElement não funciona**: Verifique se está em Info.plist corretamente
4. **App não aparece no menu bar**: Verifique se LSUIElement está configurado

### Permissões

A aplicação pode solicitar:
- **Full Disk Access**: System Settings > Privacy & Security > Full Disk Access
- **Automation**: Para executar comandos shell

## Testando a Aplicação

1. Clique no ícone no menu bar
2. Veja as estatísticas de disco
3. Teste um scan (botão refresh)
4. Teste limpeza em uma categoria segura primeiro (ex: Temp Files)
5. Verifique os resultados

---

**Pronto!** Sua aplicação MAC-LIMPO estará rodando no menu bar! 🎉
