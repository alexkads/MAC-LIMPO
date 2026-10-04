---
description: Disk X-Ray — veja para onde vai cada gigabyte do seu Mac com uma leitura rápida do disco inteiro, um mapa por tipo de arquivo, a árvore de pastas e os maiores arquivos.
---

# Disk X-Ray

Abra pelo botão :material-radiology-box: no topo do popover da barra de menus.

![Disk X-Ray](assets/images/disk-xray-light.png#only-light){ .screenshot }
![Disk X-Ray](assets/images/disk-xray-dark.png#only-dark){ .screenshot }

## O que aparece

- **Resumo** — disco usado e livre, uma barra dividida por tipo de arquivo e um cartão por categoria (vídeo, imagens, código-fonte, builds e bibliotecas, imagens de disco e VMs, dados e bancos, arquivos e instaladores, documentos, áudio…). Clique num cartão para destacar o tipo no mapa.
- **Folders** — uma árvore nativa e ordenável (tamanho, fatia da pasta-pai, arquivos, modificação). Continua rápida com milhões de itens.
- **Largest Files** — os maiores arquivos de qualquer lugar do disco.
- **Tipos** — cada categoria e suas extensões, com tamanhos e quantidades; clique para destacar.
- **Mapa** — cada arquivo é um bloco, do tamanho do espaço que ocupa e com a cor do seu tipo. Pastas grandes ganham um cabeçalho com nome e tamanho.

## Usando o mapa

| Ação | Resultado |
|---|---|
| Clique | Seleciona o arquivo ou a pasta (a árvore acompanha) |
| Duplo clique | Entra na pasta (zoom) |
| Trilha / ⟨ | Volta um nível |
| Rolar | Seleciona a pasta-pai / o filho |
| ⌘ + rolar | Zoom para dentro / para fora |
| Botão direito | Quick Look, Abrir, Mostrar no Finder, Copiar Caminho, Mover para a Lixeira |
| Espaço | Quick Look da seleção |

## Opções da barra de ferramentas

- **On Disk / Logical** — *On Disk* é o espaço que os arquivos ocupam de verdade; *Logical* é o tamanho que eles declaram. Os dois diferem em arquivos esparsos (uma imagem do Docker pode declarar 500 GB e ocupar 30 GB) e comprimidos.
- **Free** e **System** — somam ao mapa o espaço livre e o que a leitura não alcança (o próprio macOS, Preboot, swap, pastas protegidas), para a conta fechar com o disco inteiro.
- **Alvo** — o disco inteiro ou uma pasta à sua escolha.

## Por que é rápido

O scanner lê cada pasta em lote com `getattrlistbulk(2)` — nomes, tamanhos e datas de centenas de itens por chamada — usando várias threads ajustadas ao Mac (uma por núcleo em SSD, menos em discos mecânicos e volumes de rede). Num Mac de 10 núcleos ele lê ~3 milhões de itens em cerca de 16 segundos. Hardlinks contam uma vez, e montagens virtuais (como um iPhone conectado) ficam de fora.

!!! note "Acesso Total ao Disco"
    Sem o Acesso Total ao Disco algumas pastas protegidas não podem ser lidas; o espaço delas aparece em **System**.
    Conceda em Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco.
