# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### ✨ Adicionado
- **Atualização automática, como no VintageLightbox**: com as Command Line Tools ou o Xcode, a versão nova é compilada sozinha em segundo plano (`nice`), sem clique e sem fechar o app — o `install.sh --in-background` troca o bundle no disco; a faixa diz "Versão X instalada — entra na próxima abertura, ou Reabrir Agora" e sai uma notificação. A versão instalada é conferida no disco; uma falha não é retentada sozinha por 24 h; uma trava impede dois instaladores e um app reaberto no meio retoma o acompanhamento.
- **Aviso de versão nova**: como no VintageLightbox, sem GitHub Actions nem conta de desenvolvedor da Apple. O app lê `docs/updates.json` (raw.githubusercontent, com o GitHub Pages de reserva) ao abrir e de hora em hora; com versão nova, o ícone da barra de menus ganha um ponto, o popover mostra uma faixa com as novidades (Atualizar · Novidades · Depois) e sai uma notificação do macOS, uma vez por versão. *Atualizar* roda o `install.sh` em segundo plano e o app reabre sozinho na versão nova; sem ferramentas de compilação, abre a página de download. *Procurar Atualizações…* nos Ajustes.
- **Inglês e português**: o app inteiro (popover, Disk X-Ray, alertas, mensagens de escaneamento e de erro, App Intents) segue o idioma do macOS — português do Brasil ou inglês. Textos que estavam em português no código viraram inglês com tradução; os nomes das categorias ganharam `displayName` traduzido (o `rawValue` segue como identidade). Catálogo em `Localization/Localizable.xcstrings`, atualizado por `make strings`; um teste falha se faltar tradução ou se um marcador (`%@`) mudar. A recomendação da Apple Intelligence responde no idioma do sistema.
- **Site no idioma do navegador**: a primeira visita de um navegador em português vai para `/pt/`; a escolha no seletor de idioma fica guardada.
- **Boas-vindas depois de instalar**: o app só existe na barra de menus, então depois de instalar ninguém sabia onde ele estava. Agora um balão sai do próprio ícone ("MAC-LIMPO lives here in the menu bar"), com *Open MAC-LIMPO* e *Got It*; se o ícone estiver escondido (notch, barra cheia), um alerta diz onde procurar. Aparece quando o `install.sh` ou o `.pkg` abrem o app e na primeira execução.
- **Disk X-Ray — lupa com pinça**: amplia o mapa até 10⁸× (um arquivo de 1 KB num disco inteiro) com pinça, roda do mouse ou ⌥ + rolar, sem precisar clicar na janela antes; arrastar/rolar desloca com inércia, e o mapa redesenha nítido durante o gesto, com camadas por baixo para nunca sobrar borda vazia. O layout é só o squarified dos tamanhos — ampliar não muda a arrumação, e a área fica proporcional ao tamanho em qualquer zoom.
- **Disk X-Ray — ir até a seleção**: ⌘↩ ou *Magnify to Fit* voa até o item, por menor que seja; selecionar na árvore ou em Largest Files leva o mapa até ele sem exagero (no máximo até a pasta dele encher a tela), e itens pequenos demais para o contorno ganham um pino com nome e tamanho. A caixa azul desliza até a nova seleção, com um pulso ao chegar.
- **Disk X-Ray — modo 3D (Metal)**: botão de cubo na barra de ferramentas; a GPU desenha o mapa como almofadas iluminadas (cushion treemap), com as pastas aparecendo como vincos, nítido quadro a quadro em qualquer zoom. O 2D continua o mesmo de antes e é o padrão.
- **Disk X-Ray — nomes e tooltip**: botão *Labels* liga/desliga os nomes dos blocos e cabeçalhos (2D e 3D); parar o ponteiro sobre um bloco mostra o nome e o tamanho numa bandeirinha 3D, como um tooltip, que vira de lado perto da borda.
- **.NET — modo agressivo**: remove SDKs de majors fora de suporte (6, 7) e bandas superadas do mesmo `major.minor` (9.0.102 com 9.0.306 instalado), preservando o SDK mais novo e a banda fixada por qualquer `global.json`; e desinstala workloads (MAUI, Android, iOS, Aspire 8…) que nenhum projeto em `~/Projects` e pastas afins usa — vários GB em `packs/`.
- **Homebrew**: além do cache, roda `brew cleanup --prune=all` (versões antigas, downloads, links quebrados) e `brew autoremove` (dependências órfãs), e lista as ferramentas grandes que você instalou e das quais nada depende, com o comando para remover.
- **iOS Simulators — runtimes órfãos**: o card aponta runtimes que o Xcode não usa mais e que continuam em `/System/Library/AssetsV2` (sobra do `simctl runtime delete`, que só desregistra), com o tamanho e o comando para remover pelo Terminal da Recuperação — a pasta é protegida pelo SIP, nem `sudo rm` apaga.
- **Docker — limpeza total (opcional)**: novo ajuste "Docker full cleanup" para máquinas de desenvolvimento. Para todos os contêineres e remove contêineres (com os logs), todas as imagens, **todos os volumes — bancos de dados incluídos**, build cache e redes. Desligado por padrão, não fica salvo entre aberturas do app e sempre pede confirmação. O card lista cada volume que será apagado.
- **Docker — caches em uso visíveis**: o card mostra os volumes de cache de build presos a um contêiner (ex.: `cargo-target` 10 GB em `recordarfotos-dev-api-1`), e volumes `*-cargo` (CARGO_HOME) passam a contar como cache.
- **Liquid Glass é o tema principal e todo nativo**: padrão para quem nunca escolheu tema e primeiro no seletor. O popover usa só componentes do sistema — `List` com `Section`, `Gauge` circular, `LabeledContent`, `Picker`, `Toggle`, `ProgressView`, `NSSearchField` — e painéis de confirmação, progresso e resultado em vidro nativo. Classic, Cyberpunk e Matrix mantêm o visual próprio.
- **Tema Liquid Glass**: tema com o vidro nativo da Apple (`glassEffect`, `GlassEffectContainer`, botões `.glass`/`.glassProminent`) nos controles e na navegação; conteúdo em preenchimentos semânticos, sem vidro sobre vidro. Respeita Reduzir Transparência, Aumentar Contraste e Reduzir Movimento.
- **Disk X-Ray com cara nova**: cores por categoria de arquivo (Vídeo, Imagens, Código, Discos virtuais…), cabeçalho com a barra do disco e cartões por categoria, painel de tipos, mapa squarified com pastas agrupadas, ladrilhos arredondados e rótulos, trilha de navegação, tamanhos no padrão do Finder e toolbar nativa da janela.
- **Instalação por script** (`docs/install.sh`): compila e instala na própria máquina, sem depender de certificado de desenvolvedor.
- **Disk X-Ray = WinDirStat no Mac** (substitui o Disk Map): port fiel da janela principal do [WinDirStat](https://github.com/windirstat/windirstat) — árvore "All Files" / "Largest Files", lista de extensões e treemap cushion sincronizados, com o layout "Rows", o sombreamento, a paleta e os padrões do código original. O scanner segue o motor do WinDirStat: leitura em lote por pasta com `getattrlistbulk(2)` (o equivalente ao `NtQueryDirectoryFile`) e workers paralelos — ~2,9 milhões de itens em ~16 s, contra ~55 s com `fts` (espaço físico real, hardlinks uma vez, montagens virtuais fora); `<Free Space>` (F6) e `<Unknown>` (F7) fecham a conta com o disco inteiro.
- **.NET SDKs**: nova categoria que remove patches superados de SDKs, runtimes e targeting packs em `/usr/local/share/dotnet` (uma senha de admin) e `~/.dotnet`. Mantém o mais novo de cada *feature band* (SDK) e de cada `major.minor` (runtime/pack); previews e packs de workload nunca são tocados.
- **Cargo/Rust**: remove toolchains rustup fixadas em versão que já foram superadas (canais, `default_toolchain` e `[overrides]` ficam) e o lixo de `~/.rustup/{downloads,tmp}`.
- **IDE Cache**: apaga extensões que o próprio editor marcou em `extensions/.obsolete` (VS Code, Cursor, Trae, Antigravity, Windsurf, Kiro) e entradas do histórico local (`User/History`) sem toque há mais de 90 dias.
- **Docker**: remove a cópia em `com.docker.install/in_progress` só quando a versão em staging não é mais nova que a instalada — uma atualização pendente é preservada.
- Novos caminhos: cache do Yarn Berry (`~/.yarn/berry/cache`), `DocumentationCache` do Xcode e índice do Continue (`~/.continue/index`).

### 🐛 Corrigido
- **"Você está em dia" logo depois de uma release**: a CDN do raw.githubusercontent (5 min) e do Pages (10 min) ainda entregava o manifesto anterior; o pedido agora fura o cache (parâmetro `t` + `Cache-Control: no-cache`).
- **Aviso de atualização derrubava o app**: a checagem de ferramentas de compilação esperava um processo na thread principal; o SwiftUI redesenhava a faixa no meio da inicialização e o app caía (`dispatch_once` recursivo). Agora só olha arquivos.
- **Docs — `sudo` na instalação**: a página de instalação e o README explicam que o comando roda sem `sudo` e que o script pede a senha sozinho quando precisa substituir uma cópia do `.pkg` (`sudo curl … | sh` não adianta; `| sudo sh` deixaria o app do root de novo).
- **Instalador (`install.sh`) sobre uma cópia do `.pkg`**: o app instalado pelo `.pkg` pertence ao root, e o script tentava apagá-lo sem `sudo` (só olhava se `/Applications` era gravável), parando em `Permission denied`. Agora confere o dono do bundle e pede a senha só nesse caso; o `--uninstall` tinha o mesmo defeito.
- **Disk X-Ray — caixas pretas no mapa**: pastas com milhares de arquivos minúsculos (`node_modules`, caches, `.git/objects`) deixavam a área deles vazia; agora ela é pintada com a cor do maior deles.
- **Disk X-Ray — caixa azul fora do lugar com zoom**: com arquivos de tamanho idêntico, o layout ampliado podia diferir do calculado (até ~300 px num disco inteiro); empates no squarified agora são decididos sempre igual e a área ampliada tem exatamente a escala do mapa a 1×.
- **iOS Simulators — runtimes órfãos**: o comando para a Recuperação usa o nome real do volume de dados (`Macintosh HD - Data` na instalação padrão, mas pode ser outro).
- **Disk X-Ray — rótulos embolados no mapa**: pastas com um filho só ou dominante (≥ 90%) viram um cabeçalho com o caminho (`Users › alexkads`), no máximo três níveis de título, tamanho alinhado à direita (sai antes de cortar o nome) e caminhos longos cortados no começo para manter a pasta final.
- **Disk X-Ray — contorno da seleção cortado**: o contorno azul era desenhado para fora do bloco e sumia nos blocos colados na borda do mapa; agora fica inteiro por dentro do bloco e da área visível.
- **Avisos no Xcode**: `Invalid Exclude` de `MAC-LIMPO.dmg`/`dmg_staging` (o `.dmg`, sua montagem e o site do MkDocs agora são gerados em `build/`, que existe em todo clone) e captura `weak`/forte de `self` no scan do Disk X-Ray.
- **Disk X-Ray — espaço vazio entre os blocos do mapa**: o recuo das pastas se acumulava a cada nível e a folga/arredondamento valia até para blocos minúsculos, ilhando os arquivos pequenos. Agora o recuo é proporcional (só em pastas grandes e rasas) e folga e cantos só existem em blocos que os comportam.
- **Disk X-Ray — navegação lenta**: a árvore virou um `NSOutlineView` nativo (virtualizado, como o list control do WinDirStat), com ícones de pasta carregados em segundo plano; o destaque por extensão no mapa deixou de varrer milhões de itens a cada movimento do mouse.
- **Disk X-Ray — threads por máquina**: a quantidade de threads e o buffer do scan são decididos pelo hardware e pelo volume (SSD: um por núcleo, 4–16; HD mecânico: 2; rede: 4 com buffer de 64 KiB), em vez de 8 fixo.
- **Versão visível**: o rodapé do popover mostra a versão e o build (`Version 1.3.10 (13)`), lidos do `Info.plist`.
- **Cards girando sem fim (era preciso reabrir o app)**: scans `async` que mediam tamanho com `du` síncrono (Logs, Project Builds, Rust Targets) prendiam as threads do pool cooperativo e travavam os demais. Agora medem fora do pool, atrás do limite global de `du`. Cada categoria também tem prazo (420s): um scan preso libera o card e não bloqueia mais o refresh. Um `du` que estoura o timeout não cai mais numa varredura lenta e sem limite, e um processo que ignora SIGTERM recebe SIGKILL.
- **Rust Targets — "Cleaning Failed" com projeto em Docker**: um `target/` que é ponto de montagem de um volume (`./backend:/app` + volume em `/app/target`) não pode ser removido enquanto o contêiner roda, e a limpeza saía como falha mesmo com o conteúdo apagado — que também ficava fora do total liberado. Agora o `target/` é esvaziado (a pasta fica), os itens vão para a Lixeira, o espaço é medido antes/depois, e o scan indica quando o diretório está montado num contêiner.
- **iOS Simulators — card com GB que não limpava**: o scan somava a pasta inteira de dispositivos, e a limpeza (`simctl erase all`) falhava com qualquer simulador ligado (CoreSimulator 405), sem liberar nada. Agora cada dispositivo tem um destino: indisponível é apagado, desligado é zerado (`erase <udid>`), ligado fica de fora do total e aparece como "in use". O espaço liberado é medido pelo próprio `simctl` antes/depois.
- **Re-scan após limpeza**: limpar uma categoria durante o scan completo reescaneia só aquela categoria, não todas.
- **Docker — volumes de cache de build**: desde a 1.3.5 todo volume nomeado não usado era preservado, inclusive caches reconstruíveis como `cargo-target`, `node-modules` e `next-cache` de projetos compose (um único `cargo-target` chegava a 53 GB, invisível ao Rust Targets por viver dentro do `Docker.raw`). Volumes não usados com esses nomes voltam a ser limpos; bancos, uploads e demais volumes de dados continuam preservados.
- **Pedidos de permissão em loop**: sem Full Disk Access, os scans de System Data, Logs e dos apps em containers (WhatsApp, Teams, Podcasts, apps criativos) abriam um diálogo do macOS por container em `~/Library/Containers` e `~/Library/Group Containers` — centenas deles — e os cards ficavam girando para sempre. Essas áreas agora são puladas sem a permissão, e o System Data informa quantas ficaram de fora.
- **Detecção de Full Disk Access**: passa a sondar o `TCC.db` do usuário; o probe antigo (`Safari/History.db`) não existe em quem nunca abriu o Safari, e o app se achava sem permissão para sempre.

### 🔄 Alterado
- **1.3.26 — versão de teste** da atualização automática: nada muda no app.
- **1.3.27 — segundo teste** da atualização automática, já com o pedido do manifesto furando o cache.
- **Requisito baixou para macOS 26.6+** (Apple silicon), o mínimo do Xcode 27/Swift 6.4 — o app não usa nada exclusivo do macOS 27. O `install.sh` confere versão principal e secundária, aponta a atualização gratuita para quem está no 26.0–26.5 e recusa Macs Intel com uma mensagem clara.

### ⚡️ Desempenho
- System Data mede os caminhos com `du` em lotes, em vez de um processo por caminho (antes eram mais de mil só nos containers).

### Planejado
- Agendamento automático de limpeza
- Notificações quando espaço está baixo
- Exportação de relatórios de limpeza
- Atalhos de teclado
- Preferências avançadas

## [1.1.0] - 2026-07-04

### ✨ Adicionado
- **Temas**: seletor com **Classic** (visual original), **Cyberpunk** (neon ciano/magenta) e **Matrix** (verde), com glow, tipografia monoespaçada e persistência da escolha.
- **Modo de limpeza agressiva** (opt-in): remove caches grandes porém regeneráveis — modelos de IA on-device do Chrome (~4 GB) e `docker image prune -a`.
- **Diálogo de confirmação** antes de qualquer limpeza, mostrando o espaço estimado.
- Novas coberturas: **Chrome/Chromium multi-profile** (Chrome, Edge, Brave, Arc) incluindo `Service Worker`; categoria **TikTok LIVE Studio**; cache do **antigravity-updater**; leftover do **Wondershare Dr.Fone**.
- Rede de testes unitários (target `MACLIMPOTests`).

### 🔒 Segurança
- Deleções vão para a **Lixeira** (reversível), com fallback para remoção definitiva só quando a Lixeira recusa o caminho.
- `du`/`rm` passam o caminho por **argumento** (sem interpolação em shell): paths com aspas/espaços deixam de quebrar.

### ⚡ Performance
- **Scan paralelo** das categorias usando os núcleos do Mac (medição de tamanho no pool do GCD, sem travar o pool cooperativo).
- **Clean All paralelo** (concorrência limitada), com progresso agregado e resultado somado.
- Correção da medição via `du` que zerava pastas grandes (subcontagem silenciosa).

### 🧹 Refatoração
- `PathBasedCleaningService`: base testada que unificou ~12 serviços baseados em path, com estratégias (item/conteúdo), filtro de idade e alvos "agressivos".
- Remoção de código morto; falhas antes silenciosas passam a registrar log.

### 📦 Build
- `create_installer.sh` mais robusto (`set -euo pipefail`, verificação de codesign/DMG) e versionado a partir do arquivo `VERSION`.

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
