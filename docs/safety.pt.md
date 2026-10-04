---
description: O que o MAC-LIMPO apaga, o que ele nunca toca e como desfazer uma limpeza.
---

# Segurança

O MAC-LIMPO remove **caches, saídas de compilação, logs e arquivos temporários** que as próprias ferramentas recriam. Ele nunca mira seus documentos, fotos, o código-fonte dos seus projetos ou os ajustes dos apps.

## Como uma limpeza funciona

1. **Escaneia antes.** Cada categoria mede o que removeria; nada é apagado durante o escaneamento.
2. **Confirma.** Limpar uma categoria ou o *Clean All* pede confirmação (dá para dispensar durante a sessão).
3. **Lixeira, quando possível.** As limpezas por caminho movem os itens para a **Lixeira**, e dá para restaurar enquanto ela não for esvaziada.
4. **Relata.** Você vê quanto foi liberado e o que não pôde ser removido.

!!! warning "Algumas remoções são definitivas"
    As categorias que delegam à ferramenta dona dos dados — `docker … prune`, `brew cleanup`, `xcrun simctl` —
    e algumas áreas do sistema removem direto, porque não existe Lixeira nesse caminho. A descrição delas avisa,
    e as maiores ou mais arriscadas (modelos de IA locais, todas as imagens do Docker sem uso, runtimes antigos de
    simulador) só rodam no modo **Aggressive cleaning**.

## O que ele nunca faz

- Apagar **volumes de dados** do Docker (bancos, uploads). Ele remove imagens sem uso, build cache, contêineres
  parados e só os volumes sem uso cujo nome indica um cache reconstruível (por exemplo `cargo-target`,
  `node-modules`, `next-cache`).
- Remover as toolchains que você usa: ficam a padrão do rustup, as de `rustup override` e as de canal
  (stable/beta/nightly), o alias `default` do nvm e o Node mais novo de cada versão principal.
- Remover um `target/` do Cargo enquanto um build está rodando.
- Enviar qualquer coisa para fora do seu Mac. Não há telemetria; as recomendações do Apple Intelligence rodam no próprio Mac.

## Permissões

- **Acesso Total ao Disco** — para medir e limpar caches protegidos (Mail, Messages, Safari, contêineres de apps). Sem ele essas áreas são puladas, nunca forçadas.
- **Senha de administrador** — pedida só para caches do sistema (por exemplo SDKs antigos do .NET) e só nas categorias que precisam.

## Disk X-Ray

O Disk X-Ray só lê. *Mover para a Lixeira* age em um item por vez, depois de confirmação, e recusa a sua pasta pessoal e as pastas de primeiro nível dela (Documentos, Mesa, Biblioteca…).

Encontrou algo que removeu demais? [Relate em privado](https://github.com/alexkads/MAC-LIMPO/security/advisories/new).
