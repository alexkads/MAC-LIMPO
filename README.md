# MAC-LIMPO

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-✓-green" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License">
</p>

**MAC-LIMPO** é uma aplicação nativa para macOS construída em SwiftUI que ajuda você a liberar espaço em disco de forma rápida e eficiente. A aplicação roda discretamente no menu bar e oferece limpeza poderosa de diversos componentes do sistema.

## ✨ Funcionalidades

### 🧹 Módulos de Limpeza

- **🐳 Docker**: Remove containers parados, imagens não utilizadas, volumes órfãos e build cache
- **🔨 Dev Packages**: Limpa caches de npm, pip, Homebrew, Cargo e CocoaPods
- **📄 Temp Files**: Remove arquivos temporários, cache de apps e DerivedData do Xcode
- **📋 Logs**: Limpa logs antigos do sistema e de aplicativos (>30 dias)
- **📦 App Cache**: Remove cache de Safari, Chrome, Firefox, Spotify e Mail

### 🎨 Interface Moderna

- Design vibrante com gradientes coloridos
- Animações suaves e micro-interações
- Tema adaptável (dark/light mode)
- Interface intuitiva no menu bar
- Cards interativos com hover effects

### 📊 Estatísticas

- Visualização de espaço em disco usado/disponível
- Estimativa de espaço recuperável por categoria
- Resultados detalhados pós-limpeza
- Tempo de execução das operações

## 🚀 Como Usar

### Pré-requisitos

- macOS 13.0 (Ventura) ou superior
- Xcode 15.0 ou superior

### Instalação

1. Clone este repositório:
```bash
git clone <repository_url>
cd MAC-LIMPO
```

2. Abra o projeto no Xcode:
```bash
open MAC-LIMPO.xcodeproj
```

3. Configure o Bundle Identifier e Team nas configurações do projeto

4. Compile e execute (⌘R)

### Uso

1. Após executar, procure o ícone de lixeira no menu bar (canto superior direito)
2. Clique no ícone para abrir a interface
3. Visualize as estimativas de espaço para cada categoria
4. Clique em qualquer card para limpar aquela categoria
5. Ou use "Clean All" para limpar todas as categorias de uma vez

## ⚙️ Estrutura do Projeto

```
MAC-LIMPO/
├── MACLIMPOApp.swift          # App principal e menu bar
├── Models/
│   ├── CleaningCategory.swift  # Definição de categorias
│   └── CleaningResult.swift    # Modelos de resultados
├── Services/
│   ├── CleaningService.swift   # Protocolo base
│   ├── DockerCleaningService.swift
│   ├── DevPackagesCleaningService.swift
│   ├── TempFilesCleaningService.swift
│   ├── LogsCleaningService.swift
│   └── AppCacheCleaningService.swift
├── Views/
│   ├── MenuBarView.swift       # View principal
│   └── Components/
│       ├── CleaningCategoryCard.swift
│       ├── StorageStatsView.swift
│       ├── CleaningProgressView.swift
│       └── ResultsView.swift
├── Utilities/
│   ├── FileSystemHelper.swift  # Operações de arquivo
│   └── ShellExecutor.swift     # Execução de comandos
└── Assets.xcassets/
```

## ⚠️ Avisos Importantes

1. **Operações Destrutivas**: Esta aplicação remove arquivos permanentemente. Sempre revise o que será removido antes de confirmar.

2. **Permissões**: Algumas operações podem requerer:
   - Full Disk Access
   - Privilégios administrativos (sudo)

3. **Backup**: Recomenda-se ter backups regulares antes de usar ferramentas de limpeza.

4. **Docker**: A limpeza do Docker remove TODOS os containers parados e imagens não utilizadas. Certifique-se de não precisar deles.

## 🛠️ Tecnologias Utilizadas

- **SwiftUI**: Framework de UI moderna da Apple
- **AppKit**: Para integração com menu bar (NSStatusItem)
- **Combine**: Para gerenciamento de estado reativo
- **Foundation**: Para operações de arquivo e sistema

## 📝 Licença

Este projeto está sob a licença MIT.

## 🤝 Contribuições

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou pull requests.

## 🎯 Roadmap

- [ ] Agendamento automático de limpeza
- [ ] Mais opções de customização
- [ ] Exclusão de diretórios específicos
- [ ] Exportação de relatórios de limpeza
- [ ] Atalhos de teclado

## 👨‍💻 Autor

Desenvolvido com ❤️ usando SwiftUI

---

**⚡ Libere espaço, ganhe performance!**
