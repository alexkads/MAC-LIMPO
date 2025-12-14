# Como Criar o Projeto no Xcode

Como não posso criar o arquivo `.xcodeproj` diretamente (requer Xcode), siga estes passos:

## Passos para Configurar no Xcode

### 1. Abrir o Xcode
- Abra o Xcode da pasta Applications

### 2. Criar Novo Projeto
- File > New > Project
- Selecione **macOS** tab
- Escolha **App**
- Clique em Next

### 3. Configurar Projeto
Preencha os campos:
- **Product Name**: `MAC-LIMPO`
- **Team**: Selecione seu time (ou None para desenvolvimento local)
- **Organization Identifier**: `com.maclimpo` (ou seu identificador)
- **Bundle Identifier**: Será `com.maclimpo.MAC-LIMPO`
- **Interface**: `SwiftUI`
- **Language**: `Swift`
- **Desmarque**: "Use Core Data" e "Include Tests"

Clique em Next

### 4. Salvar Projeto
- Navegue até: `/Users/alexkads/MAC-LIMPO`
- **IMPORTANTE**: Ao salvar, escolha a opção para **SUBSTITUIR** a pasta existente
- Ou salve com outro nome e depois copie os arquivos .swift para dentro

### 5. Adicionar Arquivos ao Projeto

No Xcode:
1. Delete o arquivo `ContentView.swift` criado automaticamente
2. Delete o arquivo `MACLIMPOApp.swift` padrão se existir
3. Clique com botão direito no grupo "MAC-LIMPO" (azul) no navigator
4. Add Files to "MAC-LIMPO"...
5. Selecione TODOS os arquivos .swift da pasta
6. Marque "Copy items if needed"
7. Clique em Add

Organize em grupos:
- Crie grupo "Models" e adicione arquivos da pasta Models/
- Crie grupo "Services" e adicione arquivos da pasta Services/
- Crie grupo "Views" e adicione arquivos da pasta Views/
- Crie grupo "Utilities" e adicione arquivos da pasta Utilities/

### 6. Configurar Info.plist

1. No Project Navigator, selecione o projeto (ícone azul no topo)
2. Selecione o Target "MAC-LIMPO"
3. Aba "Info"
4. Na seção "Custom macOS Application Target Properties":
   - Clique no + e adicione:
     - Key: `LSUIElement`
     - Type: `Boolean`
     - Value: `YES`

### 7. Configurar Deployment Target

1. Na aba "General"
2. Em "Minimum Deployments"
3. Defina "macOS" para `13.0` ou superior

### 8. Build e Executar

1. Selecione "My Mac" como destination
2. Pressione ⌘R (ou Product > Run)
3. A aplicação será compilada e executada
4. Procure o ícone de lixeira no menu bar (canto superior direito)

## Estrutura de Arquivos Esperada

```
MAC-LIMPO/
├── MAC-LIMPO.xcodeproj/
├── MACLIMPOApp.swift
├── Info.plist
├── Assets.xcassets/
├── Models/
│   ├── CleaningCategory.swift
│   └── CleaningResult.swift
├── Services/
│   ├── CleaningService.swift
│   ├── DockerCleaningService.swift
│   ├── DevPackagesCleaningService.swift
│   ├── TempFilesCleaningService.swift
│   ├── LogsCleaningService.swift
│   └── AppCacheCleaningService.swift
├── Views/
│   ├── MenuBarView.swift
│   └── Components/
│       ├── CleaningCategoryCard.swift
│       ├── StorageStatsView.swift
│       ├── CleaningProgressView.swift
│       └── ResultsView.swift
├── Utilities/
│   ├── FileSystemHelper.swift
│   └── ShellExecutor.swift
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
