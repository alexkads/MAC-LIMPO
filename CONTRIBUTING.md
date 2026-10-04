# Guia de Contribuição - MAC-LIMPO

Obrigado por considerar contribuir com o MAC-LIMPO! Este documento fornece diretrizes para contribuir com o projeto.

## 📋 Índice

- [Código de Conduta](#código-de-conduta)
- [Como Posso Contribuir?](#como-posso-contribuir)
- [Configuração do Ambiente](#configuração-do-ambiente)
- [Padrões de Código](#padrões-de-código)
- [Processo de Pull Request](#processo-de-pull-request)
- [Convenções de Commit](#convenções-de-commit)

## 🤝 Código de Conduta

### Nosso Compromisso

Estamos comprometidos em tornar a participação neste projeto uma experiência livre de assédio para todos, independentemente de:
- Idade, tamanho corporal, deficiência
- Etnia, identidade e expressão de gênero
- Nível de experiência, nacionalidade
- Aparência pessoal, raça, religião
- Identidade e orientação sexual

### Comportamento Esperado

- Use linguagem acolhedora e inclusiva
- Respeite pontos de vista e experiências diferentes
- Aceite críticas construtivas com elegância
- Foque no que é melhor para a comunidade
- Mostre empatia com outros membros

### Comportamento Inaceitável

- Uso de linguagem ou imagens sexualizadas
- Comentários insultuosos/depreciativos (trolling)
- Assédio público ou privado
- Publicar informações privadas de terceiros
- Outras condutas antiéticas ou não profissionais

## 🚀 Como Posso Contribuir?

### Reportar Bugs

Antes de criar um bug report:
1. Verifique se o bug já foi reportado
2. Colete informações sobre o bug
3. Tente reproduzir o problema

**Template de Bug Report:**
```markdown
**Descrição do Bug**
Uma descrição clara do que é o bug.

**Passos para Reproduzir**
1. Vá para '...'
2. Clique em '...'
3. Role até '...'
4. Veja o erro

**Comportamento Esperado**
O que deveria acontecer.

**Comportamento Atual**
O que está acontecendo.

**Screenshots**
Se aplicável, adicione screenshots.

**Ambiente:**
- macOS: [ex: 14.2]
- Versão do MAC-LIMPO: [ex: 1.0]
```

### Sugerir Features

**Template de Feature Request:**
```markdown
**O problema está relacionado a algo? Descreva.**
Uma descrição clara do problema. Ex: Sempre fico frustrado quando [...]

**Descreva a solução que você gostaria**
Uma descrição clara do que você quer que aconteça.

**Descreva alternativas que você considerou**
Uma descrição de soluções ou features alternativas.

**Contexto adicional**
Adicione qualquer outro contexto ou screenshots sobre a feature.
```

### Contribuir com Código

#### Áreas Prioritárias

1. **Testes**
   - Adicionar testes unitários
   - Adicionar testes de integração
   - Melhorar cobertura de testes

2. **Novos Serviços de Limpeza**
   - Limpeza de cache de aplicativos específicos
   - Limpeza de arquivos de desenvolvimento
   - Otimizações de espaço

3. **Melhorias de UI/UX**
   - Animações mais suaves
   - Feedback visual melhorado
   - Acessibilidade

4. **Performance**
   - Otimização de scans
   - Redução de uso de memória
   - Melhor paralelização

## 🛠️ Configuração do Ambiente

### Requisitos

- macOS 27.0 ou superior
- Xcode 27 ou superior
- Swift 6.4
- Git

### Setup Inicial

1. **Fork e Clone**
   ```bash
   git clone https://github.com/seu-usuario/MAC-LIMPO.git
   cd MAC-LIMPO
   ```

2. **Configurar Remote Upstream**
   ```bash
   git remote add upstream https://github.com/original/MAC-LIMPO.git
   git fetch upstream
   ```

3. **Compilar o Projeto**
   ```bash
   swift build
   ```

4. **Executar o Projeto**
   ```bash
   swift run
   ```

### Estrutura de Branches

- `main`: Branch principal, sempre estável
- `develop`: Branch de desenvolvimento
- `feature/*`: Novas funcionalidades
- `fix/*`: Correções de bugs
- `docs/*`: Melhorias de documentação

## 📝 Padrões de Código

### Swift Style Guide

Seguimos o [Swift Style Guide](https://google.github.io/swift/) do Google.

#### Nomenclatura

```swift
// Classes e Structs: PascalCase
class CleaningService { }
struct FileNode { }

// Funções e variáveis: camelCase
func scanDirectory() { }
var isScanning = false

// Constantes: camelCase
let maxDepth = 5

// Enums: PascalCase
enum CleaningCategory {
    case docker
    case xcodeCache
}
```

#### Formatação

```swift
// Indentação: 4 espaços
func example() {
    if condition {
        doSomething()
    }
}

// Linha máxima: 120 caracteres
// Quebra de linha em parâmetros longos
func longFunctionName(
    parameter1: String,
    parameter2: Int,
    parameter3: Bool
) -> Result {
    // ...
}
```

#### Comentários

```swift
// MARK: - Section Name
// Use MARK para organizar código

/// Documenta funções públicas
/// - Parameter path: Caminho do diretório
/// - Returns: FileNode com estrutura hierárquica
func scanDirectory(path: String) -> FileNode {
    // Comentários inline para lógica complexa
    let expandedPath = (path as NSString).expandingTildeInPath
    return node
}
```

### SwiftUI Best Practices

```swift
// Componentes reutilizáveis
struct CustomButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
        }
    }
}

// ViewModels para lógica
class MyViewModel: ObservableObject {
    @Published var data: [Item] = []
    
    func loadData() {
        // Lógica aqui
    }
}

// Extrair subviews complexas
private var headerView: some View {
    HStack {
        // ...
    }
}
```

### Tratamento de Erros

```swift
// Use Result type quando apropriado
func performOperation() -> Result<Data, Error> {
    do {
        let data = try riskyOperation()
        return .success(data)
    } catch {
        return .failure(error)
    }
}

// Logging apropriado
logger.log("Operação iniciada", level: .info)
logger.log("Erro: \(error)", level: .error)
```

## 🔄 Processo de Pull Request

### Antes de Submeter

1. **Atualize sua branch**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Execute os testes**
   ```bash
   swift test
   ```

3. **Compile sem warnings**
   ```bash
   swift build -c release
   ```

4. **Verifique o código**
   - Remova código comentado
   - Remova prints de debug
   - Verifique formatação

### Criando o PR

1. **Título Descritivo**
   - `feat: adiciona limpeza de cache do Chrome`
   - `fix: corrige crash ao escanear diretórios vazios`
   - `docs: atualiza README com novas instruções`

2. **Descrição Completa**
   ```markdown
   ## Descrição
   Breve descrição das mudanças.
   
   ## Tipo de Mudança
   - [ ] Bug fix
   - [ ] Nova feature
   - [ ] Breaking change
   - [ ] Documentação
   
   ## Como Testar
   1. Passo 1
   2. Passo 2
   
   ## Screenshots (se aplicável)
   
   ## Checklist
   - [ ] Código segue os padrões do projeto
   - [ ] Comentários adicionados em código complexo
   - [ ] Documentação atualizada
   - [ ] Sem warnings de compilação
   - [ ] Testado localmente
   ```

### Review Process

1. Pelo menos 1 aprovação necessária
2. CI deve passar (quando implementado)
3. Conflitos devem ser resolvidos
4. Código deve seguir os padrões

## 💬 Convenções de Commit

Usamos [Conventional Commits](https://www.conventionalcommits.org/).

### Formato

```
<tipo>[escopo opcional]: <descrição>

[corpo opcional]

[rodapé opcional]
```

### Tipos

- `feat`: Nova funcionalidade
- `fix`: Correção de bug
- `docs`: Mudanças na documentação
- `style`: Formatação, ponto e vírgula, etc
- `refactor`: Refatoração de código
- `perf`: Melhorias de performance
- `test`: Adição ou correção de testes
- `chore`: Manutenção, dependências, etc

### Exemplos

```bash
# Feature
git commit -m "feat: adiciona serviço de limpeza do Chrome"

# Bug fix
git commit -m "fix: corrige crash ao escanear diretórios vazios"

# Documentação
git commit -m "docs: atualiza README com instruções de instalação"

# Refatoração
git commit -m "refactor: extrai lógica de scan para serviço separado"

# Com escopo
git commit -m "feat(treemap): adiciona botão voltar para navegação"

# Com corpo
git commit -m "feat: adiciona scan paralelo

Implementa TaskGroup para escanear múltiplos diretórios
simultaneamente, resultando em 3-5x melhoria de performance."
```

## 🧪 Testes

### Executando Testes

```bash
# Todos os testes
swift test

# Testes específicos
swift test --filter CleaningServiceTests
```

### Escrevendo Testes

```swift
import XCTest
@testable import MAC_LIMPO

final class MyServiceTests: XCTestCase {
    var service: MyService!
    
    override func setUp() {
        super.setUp()
        service = MyService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testExample() {
        // Given
        let input = "test"
        
        // When
        let result = service.process(input)
        
        // Then
        XCTAssertEqual(result, "expected")
    }
}
```

## 📋 Mantendo o Changelog

Todas as mudanças notáveis devem ser documentadas no [CHANGELOG.md](CHANGELOG.md).

### Ao Contribuir

Quando seu PR adiciona funcionalidades ou corrige bugs:

1. **Adicione uma entrada em `[Unreleased]`**
   ```markdown
   ## [Unreleased]
   
   ### Adicionado
   - Nova categoria de limpeza para cache do VS Code (#123)
   
   ### Corrigido
   - Crash ao escanear diretórios sem permissão (#124)
   ```

2. **Use o tipo apropriado:**
   - `Adicionado`: Novas funcionalidades
   - `Modificado`: Mudanças em funcionalidades existentes
   - `Descontinuado`: Funcionalidades que serão removidas
   - `Removido`: Funcionalidades removidas
   - `Corrigido`: Correções de bugs
   - `Segurança`: Vulnerabilidades corrigidas

3. **Seja descritivo mas conciso**
   - Explique o que mudou
   - Referencie issues quando aplicável
   - Use linguagem clara

### Exemplo de Entrada

```markdown
### Adicionado
- Suporte para limpeza de cache do VS Code com detecção automática de versões instaladas (#45)
- Opção para excluir diretórios específicos da limpeza (#67)

### Corrigido
- Crash ao escanear diretórios protegidos do sistema (#89)
- Progresso incorreto durante scan paralelo (#92)
```

## 📚 Recursos Adicionais

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Git Best Practices](https://git-scm.com/book/en/v2)

## ❓ Dúvidas?

- Abra uma issue com a tag `question`
- Entre em contato com os mantenedores

---

**Obrigado por contribuir! 🎉**
