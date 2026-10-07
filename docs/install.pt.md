---
description: Instale o MAC-LIMPO no macOS — um comando que compila no seu Mac, o instalador .pkg ou pelo código com o Xcode.
---

# Instalar

## Um comando (recomendado)

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
```

O que ele faz, nesta ordem:

1. Confere o Mac: macOS 26.6+, as Command Line Tools (ou o Xcode) com Swift 6.4 e ~2 GB livres.
2. Baixa o código da [última versão](https://github.com/alexkads/MAC-LIMPO/releases/latest) (ou da `main`, se ainda não houver nenhuma).
3. Compila o app com o `Scripts/bundle-app.sh` — de 2 a 5 minutos na primeira vez; as atualizações reaproveitam o cache em `~/Library/Caches/MAC-LIMPO-build`.
4. Instala o `MAC-LIMPO.app` em `/Applications` (ou em `~/Applications`, se não houver permissão) e abre.

!!! info "Por que compilar em vez de baixar?"
    O MAC-LIMPO não é assinado com um Developer ID pago da Apple. O macOS interroga os apps que chegam pela
    internet — eles vêm com a marca de *quarentena* — e bloqueia os não assinados com "não foi possível
    verificar se está livre de malware". Um app que sai do compilador do seu próprio Mac nunca teve essa marca
    e abre normalmente no primeiro clique.

### Opções

Com `curl | sh`, passe as opções depois de `sh -s --`:

| Opção | Efeito |
|---|---|
| `--version <ref>` | Compila uma tag (`v1.3.16`) ou branch (`main`). Padrão: a última versão. |
| `--dest <pasta>` | Instala em outro lugar. Padrão: `/Applications`. |
| `--no-open` | Não abre o app no fim. |
| `--dry-run` | Mostra o que faria, sem mudar nada. |
| `--uninstall` | Remove o app e o cache de compilação. |

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --version main
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall
```

Prefere ler antes? É um script de shell simples:

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh -o install.sh
less install.sh && sh install.sh
```

### Se faltar alguma ferramenta

| Mensagem | O que fazer |
|---|---|
| *the Command Line Tools are not installed* | `xcode-select --install`, espere terminar e rode o comando de novo. |
| *needs Swift 6.4+* | Atualize as Command Line Tools em **Ajustes do Sistema › Geral › Atualização de Software**, ou instale o Xcode mais novo e rode `sudo xcode-select -s /Applications/Xcode.app`. |
| *the build failed* | As últimas linhas do log aparecem na tela; o log completo fica em `~/Library/Caches/MAC-LIMPO-build/build.log`. [Abra uma issue](https://github.com/alexkads/MAC-LIMPO/issues/new/choose) com ele. |

## Pacote de instalação (.pkg)

Cada [versão](https://github.com/alexkads/MAC-LIMPO/releases/latest) traz o `MAC-LIMPO-<versão>.pkg`. Ele não é notarizado: depois de baixar, **clique com o botão direito › Abrir** e siga o instalador. Ele põe o app em `/Applications` e o desinstalador `mac-limpo-uninstall` em `/usr/local/bin`.

## Pelo código e pelo Xcode

```bash
git clone https://github.com/alexkads/MAC-LIMPO.git
cd MAC-LIMPO
swift run          # compila e abre
make app           # monta build/app/MAC-LIMPO.app
make installer     # build/MAC-LIMPO-<versão>.pkg
```

Para trabalhar no **Xcode 27**: `open Package.swift` (ou Arquivo › Abrir e escolha a pasta). O Xcode cria o esquema `MAC-LIMPO`; ⌘R abre o app e ⌘U roda os testes.

## Depois de instalar

- O app fica na **barra de menus** (sem ícone no Dock). Clique nele para abrir o popover.
- Algumas categorias (Mail, Messages, Safari, contêineres de apps) precisam de **Acesso Total ao Disco**: Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco › ative o MAC-LIMPO. O app pede quando precisa.
- **Launch at Login** é uma opção nos ajustes do popover.

## Desinstalar

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall
```

Instalou pelo `.pkg`? Rode `sudo mac-limpo-uninstall`. Seus arquivos nunca são tocados.
