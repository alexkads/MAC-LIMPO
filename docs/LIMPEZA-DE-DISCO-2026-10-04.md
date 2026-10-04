# Limpeza de disco manual — relato e guia (04/10/2026)

Relato de uma limpeza feita à mão num MacBook de desenvolvimento (APFS, 460 GiB), do
diagnóstico ao que foi apagado, com o critério usado para decidir o que **não** apagar.
Serve de roteiro para a próxima vez e de fonte de ideias para o app (seção 7).

**Resultado:** de **55 GiB** livres (88% do volume de dados) para **119 GiB** livres (72%),
cerca de **64 GiB** recuperados, sem perder dado de projeto, banco, histórico ou configuração.

---

## 1. Medir direito (os três enganos que quase passaram)

### 1.1 `df -h /` mente: o volume de dados é outro

No macOS recente o `/` é o **volume do sistema**, selado e pequeno (aqui 13 GiB, "19% usado").
Tudo que é do usuário vive em **`/System/Volumes/Data`**:

```bash
df -h /System/Volumes/Data      # 460Gi total, 361Gi usados, 85% — o número que importa
diskutil apfs list              # "Capacity In Use By Volumes" do contêiner inteiro
```

Um relatório que leia `/` conclui, errado, que "o disco está folgado". O app já faz certo:
`FileSystemHelper.availableDiskSpace` usa a URL da home com
`volumeAvailableCapacityForImportantUsage` (que no APFS inclui o espaço purgável).

### 1.2 `du` conta montagens virtuais

`~/Library/Developer/CoreDevice/DeviceFS` marcou **29 GB**. É o sistema de arquivos de um
iPhone/iPad conectado, exposto como pasta (somente leitura). **Não ocupa nada no Mac.**
Se a soma do `du` ultrapassa o `df`, procure uma montagem assim antes de caçar arquivos.

### 1.3 Snapshots locais e purgável

`tmutil listlocalsnapshots /System/Volumes/Data` e
`diskutil apfs listSnapshots /System/Volumes/Data` — aqui 0 snapshots, então não havia espaço
escondido ali. Vale conferir **antes** de procurar em outro lugar.

### 1.4 Armadilha de shell (zsh)

`du -sh .[!.]*` em zsh falha com `no matches found` quando o padrão não casa. Use
`du -sh ./* ~/.[!.]*` com `2>/dev/null`, ou `ls -A`.

---

## 2. Onde estava o espaço (volume de dados, 361 GiB usados)

| Onde | Tamanho | O que é |
|---|---|---|
| `/Library/Developer/CoreSimulator` | 48 GB (`du`) | Runtimes e caches dos simuladores de iOS — **inflado**: `Volumes/` é a montagem do runtime (ver 3.2); o real eram ~16 GB nos `.asset` de `AssetsV2` + 3 GB de `Caches/dyld` |
| `~/Projects` | 38 GB | Código, `target/`, `node_modules` |
| `/Applications` | 37 GB | |
| `~/.vintagelightbox/target-gpui` | **25 GB** | Cache de compilação do instalador de um app próprio |
| Docker (`Library/Containers/com.docker.docker`) | 25 GB | `Docker.raw` (imagens + volumes) |
| `~/Library/Application Support` | 17 GB | Adobe, Steam, TikTok LIVE Studio… |
| `~/Downloads` | 14 GB | 12 GB só de um `InstallAssistant.pkg` do macOS |
| `/opt/homebrew` | 13 GB | |
| `~/.rustup` / `~/.cargo` | 6,5 / 2,7 GB | Toolchains; registry |
| `~/.lmstudio`, `~/.cursor`, `~/.trae`, `~/.vscode`, `~/.nvm`, `~/.gemini` | 3,4 / 3,1 / 2,6 / 4,5 / 3,2 / 2,2 GB | Dados de ferramentas |
| `~/Library/Android` | 7,3 GB | SDK |
| `/private/var` | ~12 GB | Banco do sistema, VM, temporários |

Método: de cima para baixo, `du -sh ./* | sort -rh | head`, descendo só na maior pasta de cada
nível (home → `Library` → `Developer` → …). Os três maiores itens "novos" saíram assim:
`.vintagelightbox` (oculto na home), `CoreSimulator` (fora da home, em `/Library`) e o
`.pkg` esquecido em `Downloads`.

---

## 3. O que foi apagado (com o critério)

Regra geral: **só cache regenerável, órfão ou superado**, e olhar o conteúdo antes.

| Item | Ganho | Critério de "não usado" | Custo de errar |
|---|---|---|---|
| Imagens Docker sem contêiner (`docker image prune -a -f`): `mcp/*`, `vonwig/inotifywait`, `redis:5.0` | 2,75 GB (dentro do `Docker.raw`; o macOS só recupera quando o Docker Desktop compacta o arquivo) | Nenhum contêiner (rodando ou parado) as usa | Baixam de novo no primeiro uso |
| Cache do instalador `~/.vintagelightbox/target-gpui` | 25 GB | É `target/` do cargo; nenhum `cargo`/instalador rodando (`ps`) | A próxima atualização recompila do zero (5–20 min) |
| Runtime iOS 18.3.1 (`xcrun simctl runtime delete <UUID>`) | **0 GB até agora** (ver 3.1) | `simctl list devices` não tinha **nenhum** dispositivo nesse runtime; o simulador em uso era o 26.5 | Baixa de novo pelo Xcode |
| `InstallAssistant.pkg` (macOS Big Sur) em `Downloads` | 12 GB | Instalador, baixável da Apple; os arquivos pequenos da pasta ficaram | Baixar de novo |
| `DerivedData` de um build do Xcode em `/private/tmp` | 7,9 GB | Build de 3 dias atrás, de sessão encerrada | Recompilar |
| Toolchain `1.98.0` (`rustup toolchain uninstall`) | 1,8 GB | Padrão é 1.99; o único projeto que cita 1.98 é `rust-version = "1.98"` (MSRV), que a 1.99 cumpre | Reinstalar |
| `~/.cargo/registry/src` | ~2,3 GB | Fontes extraídos; o cargo reextrai do cache `.crate` (mantido) | Reextração (segundos) |
| Node `v21.7.3` e `~/.nvm/.cache` | ~0,5 GB | Versão ímpar fora de suporte; nenhum `.nvmrc` a pede; só `npm`/`corepack` globais | `nvm install` |
| `extensions/` de LM Studio, Cursor e Trae | ~8,2 GB | **Os apps não estão instalados** (nada em `/Applications`, `mdfind`, `which`) | Reinstalar o app baixa de novo |
| Pasta de extensão que o VS Code marcou em `extensions/.obsolete` | 0,2 GB | É o que o próprio editor apagaria | Nenhum |
| `git stash` "caixa-da-atualizacao" de 26/09 | — | Nunca commitado nem usado; o código que ele tocava mudou bastante desde então; o dono confirmou o descarte | Não recuperável |

### 3.1 O `simctl runtime delete` não liberou o disco

O comando saiu com código 0 e o runtime sumiu de `simctl runtime list`, mas o **arquivo continuou**:
`/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/<hash>.asset` (8,4 GB, dono
`_nsurlsessiond`). `df` não mexeu. O `simctl` só desregistra; o asset é do `mobileassetd`, que o
descarta depois (ou nunca, sem pressão de disco). Para liberar na hora é preciso admin:
Xcode ▸ Settings ▸ Components (o "−" do runtime) ou `sudo rm -rf` do `.asset` que **não** esteja
em `simctl runtime list`/`images.plist`. Lição: depois de apagar, conferir o `df`, não o código de
saída.

### 3.2 O que sobra em `/Library/Developer/CoreSimulator`

O `du` marcou 48 GB, e quase tudo era visão duplicada: `Volumes/iOS_<build>` (16 GB) é a
**montagem** do runtime ativo, cujo arquivo real é o `.asset` de 7,9 GB em `AssetsV2`. Sobram
só o runtime em uso (iOS 26.5, simulador ligado) e `Caches/dyld` (3 GB, do próprio 26.5, dono
root, refeito no próximo boot do simulador). Nada mais a limpar sem desligar o simulador e sem
admin.

Confirmação posterior: `cargo check` do projeto principal passou depois de remover o
`registry/src`; `rustc --version` e `rustup toolchain list` mostraram o esperado.

---

## 4. O que foi preservado de propósito

- **Volumes do Docker** (16 GB): são bancos de projetos parados (`unimed360_pgdata`,
  `apibackend_postgres-data`, `recordarfotos-dev_pgdata`…) e três volumes de nome em hash que
  não deu para identificar. Só o dono de cada projeto decide. **Nunca** `docker volume prune`
  nem `docker system prune --volumes` num Docker compartilhado entre projetos.
- **Toolchains `stable` e `nightly`**: projetos as fixam em `rust-toolchain.toml`
  (`channel = "stable"` / `"nightly"`). Apagar faria o rustup baixar uma versão **mais nova** e
  mudar o comportamento do projeto.
- **Node 18, 20, 22, 23 e 24**: cada um bate com um `.nvmrc` ou é o padrão (`alias/default`).
- **`~/.gemini`** (Antigravity, instalado): conversas, "brain" e perfil de navegador são
  histórico do usuário.
- **Configuração**: `settings.json`, `mcp.json`, `credentials`, `argv.json`, `atualizacao.key`.
  Em ferramenta desinstalada, apague **`extensions/`**, nunca a pasta inteira.
- **`target/debug` e `target/release`** do projeto principal (~6 GB): cache que faz o
  desenvolvimento diário ser rápido; liberam pouco para o prejuízo.

---

## 5. Checklist para decidir "está sem uso?"

1. **O dono é um app instalado?** `ls /Applications`, `mdfind "kMDItemKind == 'Application'"`,
   `which <cli>`. App ausente → a pasta de extensões/plugins é órfã.
2. **Tem processo usando?** `ps -eo command | grep -E "cargo|rustc|<pasta>"`. (Esperar build
   alheio com `pgrep -f` dentro de um laço encontra o próprio laço.)
3. **Algum arquivo do projeto fixa essa versão?** `rust-toolchain.toml`, `rust-version`,
   `.nvmrc`, `engines`, CI. Fixou → fica.
4. **É regenerável e a que custo?** Cache de compilação: recompila. Dados: não volta.
5. **Olhar dentro antes de apagar** (`ls`, `du`, `file`): o `UX-Unimed360` de 12 GB era um
   `.pkg` mais 2 MB de documentos úteis — só o `.pkg` saiu.
6. **Medir antes e depois** com o `df` do volume de dados, e **verificar que a ferramenta
   continua funcionando** (`cargo check`, `rustc --version`, `simctl list`).

---

## 6. Comandos usados

```bash
# Docker — só imagens sem uso; contêineres e volumes ficam
docker system df
docker image prune -a -f

# Simuladores iOS — só runtime sem dispositivo
xcrun simctl runtime list
xcrun simctl list devices
xcrun simctl runtime delete <UUID>

# Rust
rustup toolchain list
rustup toolchain uninstall 1.98.0
rm -rf ~/.cargo/registry/src          # mantém registry/cache

# Node
rm -rf ~/.nvm/versions/node/v21.7.3 ~/.nvm/.cache

# Extensões obsoletas do VS Code (lê o .obsolete que o editor mantém)
python3 - <<'EOF'
import json, os, shutil
d = os.path.expanduser('~/.vscode/extensions')
for k in json.load(open(d + '/.obsolete')):
    p = os.path.join(d, k)
    if os.path.isdir(p):
        shutil.rmtree(p)
EOF
```

⚠️ O `.obsolete` **não termina com quebra de linha**: um `while read p; do …; done < lista`
ignora a última linha sem avisar. Foi o que deixou uma pasta para trás na primeira tentativa.

---

## 7. Ideias para o MAC-LIMPO

Candidatos que este relato sugere. **Conferir antes se a categoria já cobre** — esta nota não
verificou o código além do que está citado.

- **Montagens virtuais no Disk Map / System Data**: `~/Library/Developer/CoreDevice/DeviceFS`
  parece 29 GB e não existe no disco. Excluir do scan (ou detectar montagem) evita um card
  enganoso e um "apagar" inútil.
- **Runtimes de simulador sem dispositivo**: o card de iOS Simulators remove *dispositivos*
  antigos; o grosso do espaço está nos **runtimes** (`.asset` em
  `/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime`, ~8 GB cada; o `du` de
  `CoreSimulator/Volumes` os conta em dobro). `xcrun simctl runtime delete` só desregistra:
  o app precisa checar se o `.asset` saiu e, se não, orientar a remoção pelo Xcode (Components)
  ou `sudo`. Só os que `simctl list devices` não referencia.
- **Pastas de ferramentas de apps desinstalados**: detectar app ausente + dot-folder com
  `extensions/` (LM Studio, Cursor, Trae) e oferecer limpar só `extensions/`.
- **`~/.cargo/registry/src`** (regenerável a partir do cache) e **versões de Node sem `.nvmrc`
  nem alias**, com a trava de "nunca tocar em versão fixada por projeto" (a mesma ideia da
  limpeza de toolchains rustup já existente).
- **Instaladores do macOS em `Downloads`** (`InstallAssistant.pkg`, `Install macOS*.app`): são
  grandes, baixáveis de novo e fáceis de esquecer; o card de downloads antigos poderia
  destacá-los por tamanho.
- **Cache de instalador/atualizador de apps próprios** em dot-folders da home
  (`~/.<app>/target-*`): pastas com `CACHEDIR.TAG` são, por definição, descartáveis — o arquivo
  existe justamente para ferramentas de backup e limpeza as reconhecerem.
- **Docker**: manter a política atual (nunca volumes de dados), e explicar no resumo que
  `Docker.raw` **não encolhe** sozinho depois de uma limpeza — o espaço liberado fica dentro do
  arquivo até o Docker Desktop recompactar.
- **Mostrar o volume certo**: se algum relatório novo ler capacidade, usar o volume de dados
  (como o `FileSystemHelper` já faz), nunca `/`.
