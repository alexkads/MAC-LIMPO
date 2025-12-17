# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Planejado
- Agendamento automático de limpeza
- Notificações quando espaço está baixo
- Exportação de relatórios de limpeza
- Atalhos de teclado
- Preferências avançadas

## [1.0.0] - 2025-12-17

### ✨ Adicionado

#### Interface Principal
- Interface moderna no menu bar com design vibrante
- Cards interativos com gradientes coloridos e hover effects
- Visualização de espaço em disco (usado/total)
- Tema adaptável (dark/light mode)
- Animações suaves e micro-interações
- Glassmorphism e efeitos modernos

#### Módulos de Limpeza (11 categorias)
- **Docker**: Limpeza de containers, imagens, volumes e build cache
- **Xcode Cache**: Remoção de DerivedData, Archives e DeviceSupport
- **Node Modules**: Limpeza de node_modules de projetos antigos
- **Homebrew Cache**: Remoção de cache do Homebrew
- **IDE Cache**: Limpeza de cache de IDEs JetBrains (Rider, IntelliJ, etc.)
- **Temp Files**: Remoção de arquivos temporários e cache de apps
- **Terminal Logs**: Limpeza de logs de terminal (zsh, bash)
- **Messaging Apps**: Remoção de cache de WhatsApp, Telegram, Slack
- **Trash**: Esvaziamento da lixeira
- **Large Files**: Identificação e remoção de arquivos grandes (>100MB)
- **Duplicate Files**: Detecção e remoção de arquivos duplicados

#### Disk Map - Visualização Treemap
- Treemap interativo estilo WinDirStat
- Cores por tipo de arquivo (código, documentos, vídeos, imagens, arquivos compactados)
- Navegação hierárquica (zoom in/out)
- Breadcrumb navigation
- Botão "Back" para voltar ao diretório pai
- Janela separada e independente (900x700, redimensionável)
- Scan paralelo com TaskGroup (3-5x mais rápido)
- Progresso em tempo real com contador de diretórios
- Info panel com detalhes ao passar o mouse
- Seleção de diretórios com cards bonitos e gradientes
- Algoritmo squarified para melhor visualização

#### Funcionalidades do Sistema
- Execução discreta no menu bar
- Scan de todas as categorias simultaneamente
- Resultados detalhados pós-limpeza
- Tempo de execução das operações
- Estimativa de espaço recuperável por categoria
- Logging estruturado com níveis (info, warning, error)

#### Documentação
- README.md completo com screenshots e roadmap
- CONTRIBUTING.md com guia detalhado para contribuidores
- CHANGELOG.md para rastreamento de versões
- Comentários em código para funções complexas
- Templates de issues para bugs e features

### 🔧 Técnico

#### Arquitetura
- Arquitetura MVVM (Model-View-ViewModel)
- Protocolo `CleaningService` para extensibilidade
- Componentes SwiftUI reutilizáveis
- Separação clara de responsabilidades

#### Performance
- Scan paralelo de diretórios usando Swift Concurrency (TaskGroup)
- Uso eficiente de `du` para cálculo de tamanho de diretórios
- Renderização otimizada do treemap com Canvas
- Actor para gerenciamento thread-safe de progresso

#### Utilitários
- `FileSystemHelper`: Operações de arquivo e sistema
- `ShellExecutor`: Execução segura de comandos shell
- `TreemapLayout`: Algoritmo squarified para layout do treemap
- `Logger`: Sistema de logging estruturado

### 🐛 Corrigido
- Tratamento de erros em operações de arquivo
- Validação de permissões antes de operações destrutivas
- Proteção contra remoção acidental de arquivos do sistema
- Handling de diretórios vazios no scan

### 🔒 Segurança
- Validação de caminhos antes de remoção
- Proteção contra path traversal
- Confirmação antes de operações destrutivas
- Logging de todas as operações de limpeza

## [0.1.0] - 2025-12-01 (Versão Inicial)

### Adicionado
- Estrutura básica do projeto
- Integração com menu bar
- Primeiros serviços de limpeza (Docker, Xcode)
- Interface básica com SwiftUI

---

## Tipos de Mudanças

- `Adicionado` para novas funcionalidades
- `Modificado` para mudanças em funcionalidades existentes
- `Descontinuado` para funcionalidades que serão removidas
- `Removido` para funcionalidades removidas
- `Corrigido` para correções de bugs
- `Segurança` para vulnerabilidades corrigidas

## Como Manter o Changelog

### Para Contribuidores

Ao criar um Pull Request que adiciona novas funcionalidades ou corrige bugs:

1. Adicione uma entrada na seção `[Unreleased]`
2. Use o tipo de mudança apropriado
3. Descreva a mudança de forma clara e concisa
4. Referencie issues relacionadas quando aplicável

Exemplo:
```markdown
## [Unreleased]

### Adicionado
- Nova categoria de limpeza para cache do VS Code (#123)

### Corrigido
- Crash ao escanear diretórios sem permissão (#124)
```

### Para Mantenedores

Ao criar uma nova release:

1. Mova as entradas de `[Unreleased]` para uma nova seção de versão
2. Adicione a data da release
3. Atualize o link de comparação no final do arquivo
4. Crie uma tag Git com a versão

Exemplo:
```bash
# Atualizar CHANGELOG.md
# Commit das mudanças
git add CHANGELOG.md
git commit -m "chore: release v1.1.0"

# Criar tag
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

---

**Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/)**
