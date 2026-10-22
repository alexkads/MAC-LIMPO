---
description: O que o MAC-LIMPO apaga, o que ele nunca toca e como desfazer uma limpeza.
---

# Segurança

O MAC-LIMPO remove **caches, saídas de compilação, logs e arquivos temporários** que as próprias ferramentas recriam. Seus próprios arquivos nunca são apagados de vez: as categorias que mexem neles — *Downloads Antigos* e *Restos de Apps* — só movem para a Lixeira o que ficou muito tempo parado.

## Como uma limpeza funciona

1. **Escaneia antes.** Cada categoria mede o que removeria; nada é apagado durante o escaneamento.
2. **Confirma.** Limpar uma categoria ou o *Clean All* pede confirmação (dá para dispensar durante a sessão).
3. **Lixeira, quando possível.** As limpezas por caminho movem os itens para a **Lixeira**, e dá para restaurar enquanto ela não for esvaziada. O *Clean All* nunca a esvazia — só a categoria *Lixo* faz isso, e a confirmação dela avisa que é definitivo.
4. **Relata.** Você vê quanto foi liberado e o que não pôde ser removido.

!!! warning "Algumas remoções são definitivas"
    As categorias que delegam à ferramenta dona dos dados — `docker … prune`, `brew cleanup`, `xcrun simctl` —
    e algumas áreas do sistema removem direto, porque não existe Lixeira nesse caminho. A descrição delas avisa,
    e as maiores ou mais arriscadas (modelos de IA locais, todas as imagens do Docker sem uso, runtimes antigos de
    simulador, snapshots locais do Time Machine) só rodam no modo **Aggressive cleaning**.

## O que ele nunca faz

- Apagar **volumes de dados** do Docker (bancos, uploads). Ele remove imagens sem uso, build cache, contêineres
  parados e só os volumes sem uso cujo nome indica um cache reconstruível (por exemplo `cargo-target`,
  `node-modules`, `next-cache`).
- Remover as toolchains que você usa: ficam a padrão do rustup, as de `rustup override` e as de canal
  (stable/beta/nightly), o alias `default` do nvm e o Node mais novo de cada versão principal.
- Remover um `target/` do Cargo enquanto um build está rodando.
- Apagar os **Archives** do Xcode (os dSYMs das versões que você publicou) ou a configuração do SwiftPM.
- Levar uma pasta `build/` ou `dist/` sem prova de que uma ferramenta de build a criou: projeto Gradle ou
  Flutter para `build/`, pacote Python para `dist/`. As `build/` e `dist/` de JavaScript ficam.
- Levar do `/tmp` o que um programa aberto ainda pode usar — sockets, pipes, o que mudou nos últimos 7 dias —
  ou o que é de outro usuário.
- Dar um app como desinstalado só porque ele não está em /Applications: ele é procurado pelo bundle id no Mac
  inteiro, e os dados precisam estar parados há 90 dias. O estado de projeto do VS Code e do Cursor só sai
  quando o projeto não existe mais.
- Enviar qualquer coisa para fora do seu Mac. Não há telemetria; as recomendações do Apple Intelligence rodam no próprio Mac.

## Permissões

- **Acesso Total ao Disco** — para medir e limpar caches protegidos (Mail, Messages, Safari, contêineres de apps). Sem ele essas áreas são puladas, nunca forçadas.
- **Senha de administrador** — pedida só para caches do sistema (por exemplo SDKs antigos do .NET) e para os snapshots locais do Time Machine no modo agressivo, e só nas categorias que precisam.

## Disk X-Ray

O Disk X-Ray só lê. *Mover para a Lixeira* age em um item por vez, depois de confirmação, e recusa a sua pasta pessoal e as pastas de primeiro nível dela (Documentos, Mesa, Biblioteca…).

Encontrou algo que removeu demais? [Relate em privado](https://github.com/alexkads/MAC-LIMPO/security/advisories/new).
