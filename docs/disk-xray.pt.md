---
description: Disk X-Ray — veja para onde vai cada gigabyte do seu Mac com uma leitura rápida do disco inteiro, um mapa por tipo de arquivo que você amplia com a pinça (2D ou 3D com Metal), a árvore de pastas e os maiores arquivos.
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

## Mapa 3D

Ligue o botão :material-cube-outline: **3D** na barra de ferramentas e o mapa passa a ser desenhado na GPU com Metal como *almofadas* iluminadas (o cushion treemap de van Wijk & van de Wetering, o visual clássico do WinDirStat): cada arquivo é um pequeno relevo iluminado do alto à esquerda, e os vincos entre eles mostram onde uma pasta termina e a outra começa. O relevo é o mesmo em qualquer ampliação e fica nítido quadro a quadro durante a pinça e o arrasto. Todo o resto — seleção, nomes, lupa, árvore — funciona igual ao 2D, que continua sendo o padrão.

![Mapa 3D do Disk X-Ray](assets/images/disk-xray-3d-light.png#only-light){ .screenshot }
![Mapa 3D do Disk X-Ray](assets/images/disk-xray-3d-dark.png#only-dark){ .screenshot }

## Usando o mapa

| Ação | Resultado |
|---|---|
| Clique | Seleciona o arquivo ou a pasta (a árvore acompanha) |
| Duplo clique | Entra na pasta (zoom) |
| Trilha / ⟨ | Volta um nível |
| Rolar (trackpad) | Seleciona a pasta-pai / o filho |
| ⌘ + rolar | Zoom para dentro / para fora |
| Pinça (trackpad), roda do mouse ou ⌥ + rolar | Amplia o mapa em volta do cursor — arquivos pequenos ganham bloco e rótulo, até os de 1 KB. Funciona sem clicar na janela antes |
| ⌘ + Return / botão direito → Magnify to Fit | Vai até o arquivo ou a pasta selecionada, por menor que seja |
| Selecionar na árvore ou em Largest Files | O mapa vai até o item: aproxima o suficiente para ler um item pequeno (no máximo até a pasta dele encher o mapa), afasta para caber um grande, ou só desliza se o tamanho já está bom. Itens pequenos demais para o contorno — ou arquivos vazios — ganham um pino com nome e tamanho |
| Toque duplo com dois dedos | Alterna a ampliação de 4× |
| Rolar ou arrastar (ampliado) | Desloca o mapa — solte o arraste em movimento e ele desliza |
| ⌘ + / ⌘ − / ⌘ 0 | Amplia / reduz / tamanho real |
| Botão direito | Quick Look, Abrir, Mostrar no Finder, Copiar Caminho, Mover para a Lixeira |
| Parar o ponteiro sobre um bloco | O nome e o tamanho aparecem numa bandeirinha, como um tooltip |
| Espaço | Quick Look da seleção |

## Opções da barra de ferramentas

- **On Disk / Logical** — *On Disk* é o espaço que os arquivos ocupam de verdade; *Logical* é o tamanho que eles declaram. Os dois diferem em arquivos esparsos (uma imagem do Docker pode declarar 500 GB e ocupar 30 GB) e comprimidos.
- **Free** e **System** — somam ao mapa o espaço livre e o que a leitura não alcança (o próprio macOS, Preboot, swap, pastas protegidas), para a conta fechar com o disco inteiro.
- **Alvo** — o disco inteiro ou uma pasta à sua escolha.
- **Labels** — nomes nos blocos e cabeçalhos das pastas, no 2D e no 3D. Desligado, o mapa fica limpo e os nomes aparecem só no tooltip.
- **3D** — desenha o mapa na GPU (Metal) como almofadas iluminadas: cada arquivo vira um pequeno relevo e as pastas aparecem como vincos, então a hierarquia se lê sem molduras, e o zoom fica nítido quadro a quadro. Os nomes ficam nos blocos como no 2D, e parar o ponteiro sobre um bloco mostra o nome e o tamanho numa bandeirinha 3D, como um tooltip. Desligado, o mapa é o 2D plano. A escolha fica salva.

## Por que é rápido

O scanner lê cada pasta em lote com `getattrlistbulk(2)` — nomes, tamanhos e datas de centenas de itens por chamada — usando várias threads ajustadas ao Mac (uma por núcleo em SSD, menos em discos mecânicos e volumes de rede). Num Mac de 10 núcleos ele lê ~3 milhões de itens em cerca de 16 segundos. Hardlinks contam uma vez, e montagens virtuais (como um iPhone conectado) ficam de fora.

!!! note "Acesso Total ao Disco"
    Sem o Acesso Total ao Disco algumas pastas protegidas não podem ser lidas; o espaço delas aparece em **System**.
    Conceda em Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco.
