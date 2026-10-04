---
description: Limpador de disco gratuito e de código aberto para macOS, feito para desenvolvedores — limpe Xcode, Docker, simuladores, node_modules e mais de 40 caches pela barra de menus.
---

<div class="hero" markdown>

# MAC-LIMPO

<p class="tagline">Libere espaço no seu Mac — um limpador nativo na barra de menus, feito para desenvolvedores,<br>com um raio-x que mostra para onde vai cada gigabyte.</p>

[Instalar :material-download:](install.md){ .md-button .md-button--primary }
[Ver no GitHub :fontawesome-brands-github:](https://github.com/alexkads/MAC-LIMPO){ .md-button }

</div>

![Disk X-Ray](assets/images/disk-xray-light.png#only-light){ .screenshot }
![Disk X-Ray](assets/images/disk-xray-dark.png#only-dark){ .screenshot }

## Instale com um comando

<div class="install-command" markdown>

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
```

</div>

O script compila o MAC-LIMPO **no seu Mac** e instala em `/Applications`. Compilado localmente, o app abre no primeiro clique — sem aviso do Gatekeeper e sem certificado pago. Precisa do macOS 27+ e das Command Line Tools. [Mais opções →](install.md)

## O que ele faz

<div class="grid cards" markdown>

-   :material-broom: **46 categorias de limpeza**

    ---

    Xcode, simuladores, Docker, `node_modules`, `target/` do Rust, Cargo, Go, pnpm, Bun, Android SDK, .NET, caches de IDEs, navegadores, logs, temporários e mais.

    [:octicons-arrow-right-24: Categorias](cleaning.md)

-   :material-radiology-box: **Disk X-Ray**

    ---

    Lê cada arquivo em segundos e mapeia o disco por tipo: árvore de pastas, painel de tipos, maiores arquivos e um mapa interativo.

    [:octicons-arrow-right-24: Disk X-Ray](disk-xray.md)

-   :material-shield-check: **Seguro por padrão**

    ---

    Escaneia antes, confirma, Lixeira em vez de apagar quando possível, só caches — nunca seus documentos.

    [:octicons-arrow-right-24: Segurança](safety.md)

-   :material-apple: **Nativo**

    ---

    SwiftUI + AppKit, Liquid Glass por padrão, recomendações do Apple Intelligence, App Intents para Atalhos e Siri. Sem telemetria, sem conta.

    [:octicons-arrow-right-24: FAQ](faq.md)

</div>

## Barra de menus

<figure markdown>
![Popover da barra de menus](assets/images/menu-bar-light.png#only-light){ width="320" .screenshot }
![Popover da barra de menus](assets/images/menu-bar-dark.png#only-dark){ width="320" .screenshot }
</figure>

Clique no ícone da barra de menus: o popover mostra o uso do disco e cada categoria com quanto liberaria. Clique numa categoria para limpá-la, ou em **Clean All**.

## Software livre

O MAC-LIMPO é distribuído sob a [GPL-3.0-or-later](https://github.com/alexkads/MAC-LIMPO/blob/main/LICENSE). Relatos de bugs, ideias e pull requests são bem-vindos — veja o [guia de desenvolvimento](development.md).
