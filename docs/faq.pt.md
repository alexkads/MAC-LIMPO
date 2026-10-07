---
description: Perguntas frequentes sobre o MAC-LIMPO.
---

# Perguntas frequentes

??? question "É grátis? Qual é a pegadinha?"
    É software livre, sob a GPL-3.0-or-later. Sem conta, sem assinatura, sem anúncios, sem telemetria.

??? question "Por que o script de instalação compila o app?"
    O projeto não paga por um Developer ID da Apple. O macOS bloqueia apps não assinados baixados da internet;
    um app compilado no seu próprio Mac não fica em quarentena e abre normalmente. Veja [Instalar](install.md).

??? question "Quais versões do macOS são suportadas?"
    macOS 26.6 ou mais novo, em Apple silicon. Compilar exige as Command Line Tools ou o Xcode com Swift 6.4.

??? question "Em quais idiomas ele funciona?"
    Inglês e português do Brasil. O app segue o idioma do seu Mac (Ajustes do Sistema › Geral › Idioma e
    Região) e usa inglês para qualquer outro idioma. Este site abre em português para navegadores em português;
    o seletor de idioma no topo troca, e a sua escolha fica guardada.

??? question "Ele vai apagar meus arquivos?"
    Ele mira caches, saídas de compilação e temporários que as ferramentas recriam. As limpezas por caminho
    movem para a Lixeira. Veja [Segurança](safety.md) para os detalhes e as exceções.

??? question "Por que o espaço liberado não aparece na hora?"
    Itens na Lixeira ainda ocupam espaço até você esvaziá-la. A imagem de disco do Docker (`Docker.raw`) só
    encolhe depois que o Docker Desktop a compacta. O APFS também pode levar um instante para atualizar o livre.

??? question "Por que parte do disco aparece como 'System & Unaccounted' no Disk X-Ray?"
    É o espaço em uso que a leitura não consegue ver arquivo por arquivo: o próprio macOS (volume do sistema
    selado), Preboot, swap, Recovery e pastas protegidas pela privacidade. Com o Acesso Total ao Disco ele diminui.

??? question "Dá para usar pelo Atalhos ou pela Siri?"
    Sim — o MAC-LIMPO tem dois App Intents, *Scan Mac Storage* e *Clean Mac Storage*.

??? question "Como desinstalo?"
    `curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall`, ou
    `sudo mac-limpo-uninstall` se você usou o `.pkg`.

??? question "Como posso ajudar?"
    Relate bugs, sugira categorias de limpeza ou envie um pull request — veja o
    [guia de desenvolvimento](development.md).
