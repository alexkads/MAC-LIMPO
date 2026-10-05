<div align="center">

# MAC-LIMPO

**Libere espaço no seu Mac — um limpador nativo na barra de menus, feito para desenvolvedores, com um raio-x do disco que mostra para onde vai cada gigabyte.** Gratuito e de código aberto: uma alternativa ao CleanMyMac para limpar e ao DaisyDisk para analisar o espaço em disco.

[![Licença: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![macOS 27+](https://img.shields.io/badge/macOS-27%2B-black?logo=apple)](https://alexkads.github.io/MAC-LIMPO/pt/install/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Última versão](https://img.shields.io/github/v/release/alexkads/MAC-LIMPO)](https://github.com/alexkads/MAC-LIMPO/releases/latest)

[Site](https://alexkads.github.io/MAC-LIMPO/pt/) · [Instalar](#instalar) · [Recursos](#recursos) · [Contribuir](CONTRIBUTING.md) · [English](README.md)

<img src="docs/assets/images/disk-xray-light.png" alt="Disk X-Ray: tipos de arquivo, árvore de pastas e mapa do disco" width="860">

</div>

## Por quê

Xcode, Docker, simuladores, `node_modules`, pastas `target/` do Rust, caches de pacotes e modelos de IA ocupam centenas de gigabytes sem você perceber. O MAC-LIMPO encontra tudo isso, mostra quanto cada um ocupa e limpa — mandando para a Lixeira sempre que possível, para dar para desfazer.

É um app nativo (SwiftUI + AppKit) que mora na barra de menus. Sem telemetria, sem conta, sem assinatura.

## Instalar

### Um comando (recomendado)

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
```

O script confere o seu Mac, baixa o código da última versão, **compila na sua máquina** e instala o `MAC-LIMPO.app` em `/Applications`. Como o app sai do compilador do próprio Mac, ele nunca recebe a marca de quarentena e abre no primeiro clique — sem certificado de desenvolvedor e sem aviso do Gatekeeper. Se quiser, [leia o script](docs/install.sh) antes.

Requisitos: **macOS 27 ou mais novo** e as **Command Line Tools** (`xcode-select --install`) ou o Xcode, com Swift 6.4. A primeira compilação leva de 2 a 5 minutos.

```bash
# Opções: compilar uma branch, escolher a pasta, simular ou desinstalar
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --version main
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --dest ~/Applications
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --dry-run
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall
```

### Pacote de instalação

Cada [versão](https://github.com/alexkads/MAC-LIMPO/releases/latest) tem um `.pkg`. Ele não é notarizado: depois de baixar, clique com o botão direito e escolha **Abrir**.

### Pelo código / Xcode

```bash
git clone https://github.com/alexkads/MAC-LIMPO.git
cd MAC-LIMPO
swift run                 # compila e abre (procure o ícone na barra de menus)
open Package.swift        # ou abra no Xcode 27 e aperte ⌘R
make app                  # monta build/app/MAC-LIMPO.app
```

Mais detalhes no [guia de instalação](https://alexkads.github.io/MAC-LIMPO/pt/install/).

## Recursos

<img src="docs/assets/images/menu-bar-light.png" alt="Popover do MAC-LIMPO com o uso do disco e as categorias de limpeza" width="300" align="right">

**46 categorias de limpeza**, agrupadas e medidas antes de qualquer remoção:

- **Desenvolvimento** — DerivedData e archives do Xcode, simuladores iOS, imagens e build cache do Docker, `node_modules`, `target/` do Rust, Cargo, Go, pnpm, Bun, npm/pip, NuGet, pub (Dart/Flutter), Android SDK, SDKs do .NET, versões antigas do Node (nvm), caches de IDEs (VS Code, Cursor, JetBrains, Zed), Playwright, Cypress, Expo, modelos de IA locais.
- **Sistema** — logs, arquivos temporários, `/var/folders`, caches de apps, Lixeira, System Data.
- **Apps e navegadores** — caches do Safari/Chrome/Firefox, Spotify, Adobe, Notion, apps criativos, restos de apps desinstalados.
- **Comunicação** — Slack, anexos do Messages e do Mail, caches do WhatsApp/Teams/Discord.

**Disk X-Ray** — o mapa completo do disco: cada arquivo lido em segundos (milhões de itens), um mapa colorido por tipo de arquivo, a árvore de pastas, o painel de tipos e os maiores arquivos. Faça a pinça (ou use a roda do mouse) para ampliar até um único arquivo de 1 KB e arraste para deslocar, como num mapa; ⌘↩ voa até o item selecionado. Troque para o **mapa 3D**, desenhado na GPU com Metal como almofadas iluminadas, em que as pastas aparecem como vincos. Duplo clique para entrar numa pasta, Quick Look, Mostrar no Finder, Mover para a Lixeira.

<img src="docs/assets/images/disk-xray-3d-light.png" alt="Disk X-Ray em 3D: o mapa desenhado como almofadas iluminadas com Metal" width="860">

**Seguro por padrão** — escaneia antes, confirma antes de limpar, Lixeira em vez de apagar quando possível e só caches (nunca seus documentos). Veja [o que ele limpa e por que é seguro](https://alexkads.github.io/MAC-LIMPO/pt/safety/).

**Visual nativo** — o tema padrão *Liquid Glass* usa só componentes do sistema; os temas Classic, Cyberpunk e Matrix estão a um clique. O Apple Intelligence escreve uma recomendação de armazenamento no próprio Mac, e os App Intents levam a limpeza para o Atalhos e a Siri.

<br clear="right">

## Contribuir

Contribuições são bem-vindas — principalmente novas categorias de limpeza. Leia o [CONTRIBUTING.md](CONTRIBUTING.md), o [Código de Conduta](CODE_OF_CONDUCT.md) e o [guia de desenvolvimento](https://alexkads.github.io/MAC-LIMPO/development/). Falhas de segurança: veja o [SECURITY.md](SECURITY.md).

## Licença

O MAC-LIMPO é software livre, distribuído sob a [GNU General Public License v3.0 ou posterior](LICENSE). Veja o [NOTICE](NOTICE) para os créditos — o Disk X-Ray é inspirado no [WinDirStat](https://github.com/windirstat/windirstat).

Copyright © 2025-2026 Alex S S Fonseca e colaboradores.
