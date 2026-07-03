# MAC-LIMPO — Plano de Refatoração de Qualidade & Segurança

> Origem: análise de estrutura/qualidade do código (jul/2026). Este documento é o plano
> de execução. Cada fase tem escopo, arquivos afetados, critério de aceite e risco.
> Ordem = prioridade (segurança do usuário → correção → manutenção).

## Objetivos

1. **Não apagar dados do usuário sem confirmação e sem possibilidade de desfazer.**
2. **Não subcontar espaço** (medição de tamanho confiável).
3. **Eliminar a duplicação** de ~25 services quase idênticos.
4. **Concorrência honesta** (nada de `async` que bloqueia thread; nada de tempestade de `du` no launch).
5. **Erros visíveis** (parar de engolir falhas silenciosamente).
6. **Rede de segurança de testes** para a lógica que deleta arquivos.

## Princípios

- Build verde após **cada** fase (`swift build`), formatação/lint limpos (`swiftformat . && swiftlint`).
- Mudanças incrementais e revisáveis; sem big-bang.
- Preferir APIs de `FileManager` a interpolar paths em shell.
- Comportamento observável só muda onde é o objetivo (segurança); refactors são de comportamento-preservador.

---

## Fase 0 — Baseline & rede de testes

**Escopo**
- Confirmar árvore limpa e build verde como ponto de partida.
- Adicionar um **test target** ao `Package.swift` (hoje não existe nenhum).
- Testes de caracterização das funções puras (sem risco, fixam o comportamento atual):
  - `FileSystemHelper.formatBytes`
  - `FileSystemHelper.expandPath`
  - parsing de tamanho do `du` (extrair p/ função testável)
  - montagem de `CleaningResult`/`ScanResult`

**Arquivos**: `Package.swift` (+ `.testTarget`), novo `Tests/MACLIMPOTests/`.

**Aceite**: `swift test` roda e passa; build do executável intacto.
**Risco**: baixo. SPM com executable + test target exige mover fontes p/ um target de biblioteca OU usar `@testable import` — ver nota de arquitetura abaixo.

> **Nota SPM**: o executável tem `path: "."` com `sources:` explícito. Para testar,
> a opção de menor atrito é criar um alvo de **biblioteca** `MACLIMPOCore` com a lógica
> (Models/Services/Utilities) e deixar o executável só com a camada App/UI. Se isso for
> muito invasivo agora, alternativa: manter tudo no executável e testar via um target de
> teste que compila os mesmos fontes. Decisão registrada na execução da Fase 0.

---

## Fase 1 — `PathBasedCleaningService` (matar a duplicação)

**Problema**: 25/35 services repetem o mesmo esqueleto (lista de paths → soma de tamanho no
`scan` → remoção no `clean` → montagem do resultado).

**Escopo**
- Novo `Services/PathBasedCleaningService.swift`: classe base parametrizada por
  `category` + `[CleanTarget]` (path + rótulo opcional + filtro de idade opcional).
- Implementa `scan`/`clean` **uma única vez**, com logging consistente.
- Migrar os services path-based para subclassar/configurar a base:
  Homebrew, Cargo, Playwright, pnpm, Go, DevApiTools, Notion, Cypress, AITools,
  VarFolders, CreativeApps, Podcasts, TerminalLogs, IDECache, AndroidSDK, Adobe,
  Spotify, Slack, MessagingApps, BrowserCache, AppCache, Xcode, Mail/Messages, Downloads.
- **Não** migrar (têm lógica própria): Docker (tool-based), SystemData (comandos de
  sistema), ProjectCleaning (varre dirs escolhidos), DiskMap.

**Arquivos**: novo base + ~25 services reescritos (cada um vira ~10-20 linhas de config);
`Package.swift` (adicionar o novo fonte).

**Aceite**: build verde; para cada service migrado, `scan` retorna o mesmo tamanho de antes
(validar em 3-4 casos com dados reais); LOC de Services cai ~40%.
**Risco**: médio (muitos arquivos). Mitigar migrando em lotes pequenos + build a cada lote.

---

## Fase 2 — Segurança: confirmação + Lixeira (reversível)

**Problema**: `cleanCategory` apaga na hora, sem diálogo; deleção é permanente (`removeItem`
+ fallback `rm -rf`). Zero confirmação no código.

**Escopo**
- `FileSystemHelper.trashItem(atPath:)` usando `FileManager.trashItem(at:resultingItemURL:)`
  → itens vão para a **Lixeira** (reversível) em vez de sumirem.
- A base da Fase 1 passa a deletar via `trashItem` por padrão; um flag por-target permite
  hard-delete só onde faz sentido (ex.: caches enormes onde a Lixeira seria contraproducente
  — decidir caso a caso, default = Lixeira).
- **Diálogo de confirmação** (`NSAlert`) antes de `cleanCategory` e `cleanAll`, mostrando
  categoria, nº de itens e tamanho estimado; opção "não perguntar de novo nesta sessão".

**Arquivos**: `Utilities/FileSystemHelper.swift`, `Services/PathBasedCleaningService.swift`,
`Views/MenuBarView.swift` (fluxo de confirmação).

**Aceite**: limpar uma categoria mostra confirmação; itens aparecem na Lixeira; cancelar não
apaga nada. Verificado manualmente com uma pasta de cache de teste.
**Risco**: baixo-médio. `trashItem` pode falhar em alguns paths de sistema → fallback logado.

---

## Fase 3 — Concorrência & correção de medição

**Problema A**: `du -sk` roda com `timeout: 5`; pastas grandes (>GBs) estouram → tamanho 0
(subcontagem silenciosa). **Problema B**: `ShellExecutor.execute` faz polling com
`Thread.sleep`, bloqueando thread cooperativa dentro de `async`. **Problema C**: `init` do
ViewModel dispara 35 scans concorrentes → tempestade de `du`.

**Escopo**
- Medição de tamanho sem timeout curto: usar timeout generoso/none para `du -sk`, ou medir
  via API. Extrair `measureSize` async.
- `ShellExecutor`: variante **async real** (`withCheckedContinuation` +
  `Process.terminationHandler`, leitura de pipe sem bloqueio) — sem `Thread.sleep`.
- Limitar concorrência dos scans iniciais (`TaskGroup` com teto, ex. 4, ou sob demanda ao
  abrir o popover).

**Arquivos**: `Utilities/ShellExecutor.swift`, `Utilities/FileSystemHelper.swift`,
`Views/MenuBarView.swift`, `Services/DiskMapService.swift` (usa medição).

**Aceite**: escanear a pasta do Docker (~8 GB) reporta tamanho real, não 0; abrir o app não
gera dezenas de processos `du` simultâneos; UI não trava.
**Risco**: médio-alto (mexe em base compartilhada e em call sites síncronos). Mitigar mantendo
uma API síncrona de compat onde necessário e migrando call sites aos poucos.

---

## Fase 4 — Tratamento de erro & remoção de código morto

**Escopo**
- Substituir `try?`/`catch {}` silenciosos por log (`logger`) nos pontos onde a falha vira
  "0 bytes" ou lista vazia sem aviso (`FileSystemHelper`, fallbacks de scan).
- Remover código morto: `BaseCleaningService.measureExecutionTime` (não usado); comentários
  obsoletos "TEMPORÁRIO/Xcode" e `// ... existing properties ...` em `MenuBarView`.
- Progresso: parar de simular com `Task.sleep`; refletir progresso real ou rotular honesto.

**Arquivos**: `Utilities/FileSystemHelper.swift`, `Services/CleaningService.swift`,
`Views/MenuBarView.swift`.

**Aceite**: nenhum `catch {}` vazio sem log em caminho de scan; grep dos comentários
obsoletos = 0; build verde.
**Risco**: baixo.

---

## Fase 5 — Endurecer o shell

**Problema**: `rm -rf '\(path)'` e `du -sk '\(path)'` quebram em paths com aspas simples;
DiskMap/ProjectCleaning recebem dirs escolhidos pelo usuário.

**Escopo**
- Preferir `FileManager` (já é o caminho primário do `removeItem`); onde shell for
  necessário, passar argumentos por **array** (`task.arguments = ["-sk", path]`) em vez de
  interpolar em `-c "..."`.
- Revisar `SystemDataCleaningService` (comandos `purge`, `atsutil`, `killall`) — documentar
  efeitos colaterais e checar exit codes em vez de `_ =`.

**Arquivos**: `Utilities/ShellExecutor.swift` (API por args), `Utilities/FileSystemHelper.swift`,
`Services/SystemDataCleaningService.swift`.

**Aceite**: medir/remover uma pasta com `'` no nome funciona; sem regressão.
**Risco**: baixo-médio.

---

## Fase 6 — Testes da lógica de limpeza & verificação final

**Escopo**
- Testes do `PathBasedCleaningService` usando diretórios temporários reais (criar arquivos,
  medir, limpar p/ Lixeira, assertir bytes/contagem/erros).
- Teste do parsing de `du`, `trashItem`, e do fluxo de confirmação (lógica isolável).
- Passada final: `swift build && swift test && swiftformat . && swiftlint`.
- Verificação manual do app (popover + Disk Map) com `swift run`.

**Aceite**: `swift test` verde; app abre, confirma antes de limpar, itens vão p/ Lixeira,
tamanhos corretos.
**Risco**: baixo.

---

## Fora de escopo (backlog separado — ligado à análise "liberar mais espaço")

Estes são **features**, não qualidade; ficam para depois do refactor:
- Chrome multi-profile + `Service Worker` no `BrowserCacheCleaningService`.
- Docker: `volume prune`, modo agressivo `image prune -a`, aviso sobre `Docker.raw`.
- Services novos: TikTok LIVE Studio, Antigravity, Wondershare (leftovers).
- Modo "limpeza agressiva" opt-in (modelos IA regeneráveis do Chrome).

## Sequência de execução

`Fase 0 → 1 → 2 → 3 → 4 → 5 → 6`, com build/format/lint verdes entre fases.
Trabalho em branch dedicada (`refactor/quality-safety`), commits por fase.

## Checklist de progresso

- [x] Fase 0 — Baseline & testes das funções puras (test target via `@testable import`)
- [x] Fase 1 — `PathBasedCleaningService` + migração de 12 services
- [x] Fase 2 — Confirmação (NSAlert) + Lixeira (`trashItem`, flag `useTrash`)
- [x] Fase 3 — `du` timeout 120s + cap de 4 scans + ShellExecutor sem busy-wait/deadlock
- [x] Fase 4 — Erros de disco logados + remoção de código morto
- [x] Fase 5 — `du`/`rm` por argumentos (`ShellExecutor.run`), sem interpolação
- [x] Fase 6 — 19 testes verdes; build debug+release; format/lint sem erro; app sobe

## Concluído — resumo

19 testes (FileSystemHelper, PathBasedCleaningService, ShellExecutor). Services caíram
~800 LOC. Deleção reversível (Lixeira) + confirmação para todas as categorias.

## Diferido (follow-up, não bloqueante)

- **Async real no ShellExecutor**: hoje é síncrono (sem busy-wait, mas ainda bloqueia a
  thread chamadora). Cap de concorrência mitiga. Migração completa p/ `withCheckedContinuation`
  fica para depois.
- **Migrar services restantes** com lógica própria para helpers compartilhados quando fizer
  sentido (ex.: age filter do Downloads/Logs já cabe no `CleanTarget.olderThanDays`).
- **72 warnings de SwiftLint** de estilo (for_where, identifier_name, etc.) — incremental.
- Backlog de features (Chrome multi-profile, Docker volumes, apps novos) — seção acima.
