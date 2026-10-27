# Exportar para Foundry (Nauren) — mod do Dungeondraft

Exporta o mapa no formato que o importador **DD2VTT URL Importer** (Foundry) usa melhor:

- `.dd2vtt` **sem a imagem** (arquivo leve, só paredes, portas, janelas e luzes);
- a **imagem separada**, em WebP, PNG ou JPEG, saindo da mesma exportação (nunca fica desencontrada);
- com vários andares, o **número e o nome do andar** no nome dos arquivos (`Casa_1_Terreo.dd2vtt` + `Casa_1_Terreo.webp`);
- em cada porta e janela, **qual moldura/batente foi usado** e, nas portas, a **abertura medida pela própria arte da moldura**.

No Foundry, o importador usa isso para escolher sozinho a folha da porta que combina com a moldura e para encaixar a folha exatamente entre os postes.

## Instalação

1. Feche o Dungeondraft.
2. Copie a pasta `NaurenFoundryExport` para a pasta de mods que você já usa (a mesma do Soft Shadows, Unofficial Patch etc.).
3. Abra o Dungeondraft e, na tela inicial, ative **Exportar para Foundry (Nauren)** na lista de mods (junto com os que você já usa).
4. Abra um mapa.

## Exportar um andar

1. **Arquivo → Exportar** (a janela normal de exportação).
2. Em **formato**, escolha uma das opções novas:
   - **Foundry Nauren (WebP)** ← recomendado (leve, boa qualidade);
   - **Foundry Nauren (PNG)** (maior, sem perda);
   - **Foundry Nauren (JPEG)** (mais leve, perde um pouco).
3. Ajuste a resolução (PPI) e a qualidade como sempre, escolha o andar em "Source level" e clique em **Exportar**.
4. Ao terminar aparece um aviso com os dois arquivos gravados e quantas portas tiveram a moldura identificada.

## Exportar todos os andares

1. Na janela de exportação, com um formato "Foundry Nauren" escolhido, marque **Exportar todos os andares de uma vez** (caixa "Foundry (Nauren)").
2. Clique em **Exportar** uma vez, como sempre.
3. O mod exporta o andar escolhido e depois os outros sozinho, com o mesmo formato, PPI e opções. A janela mostra "X de Y prontos". No fim aparece a lista de tudo que foi gravado.
4. **Cancelar a sequência de andares** (na mesma caixa) interrompe; o que já foi exportado fica.

Os arquivos saem com o mesmo nome base e o número/nome de cada andar (`Casa_1_Terreo`, `Casa_2_Primeiro`...).

## Paredes com "Allow Light" (varandas, grades, parapeitos)

O botão **Allow Light** da ferramenta de parede vem do Unofficial Patch. O `.dd2vtt` normal do Dungeondraft não guarda essa marcação (no Foundry viraria parede comum), então o mod grava a lista dessas paredes no arquivo. No importador, em **Luzes → Paredes com "Allow Light"**, escolha:

- **Luz e visão passam, ninguém atravessa** (padrão) — varanda, grade, parapeito;
- **Só a luz passa** — a visão continua bloqueada;
- **Parede comum**.

O aviso do fim da exportação e o log mostram quantas paredes com Allow Light foram gravadas.

## No Foundry

- No importador, escolha **todos os `.dd2vtt` de uma vez** (ou arraste todos): ele cria um cartão por andar, já na ordem e com o nome de cada andar, e mostra qual imagem colar em cada um.
- Suba as imagens no Imgur (ou onde preferir) e cole a URL de cada andar.
- Com **Arte pela moldura** ligado, cada porta/janela recebe a folha do mesmo material e cor da moldura usada no Dungeondraft.

## Compatibilidade

Verificado contra: Asset Inspector 1.3.3, Better Terrain Tool 1.1.2, ColourAndModifyThings 1.5.2, Layers Panel 1.2.3, Soft Shadows 1.7.4, Unofficial Patch 1.7.3.

- Nenhum deles registra formato de exportação: as opções "Foundry Nauren" não disputam com nada.
- O mod só **acrescenta** a própria caixa na janela de exportação (com nome próprio, antes da linha de botões); não move nem altera os controles dos outros mods.
- Se o Unofficial Patch estiver exportando a **imagem de traço**, ela fica na camada de objetos durante a exportação; o mod detecta isso e pula só as paredes dos objetos (aviso no log), em vez de travar.

## Dicas

- **Imgur e PNG:** o Imgur transforma PNG acima de 5 MB em JPG, e o fundo transparente vira branco. Prefira **WebP** ou um PPI menor (100 a 150 já basta no Foundry). O mod avisa quando o PNG passa de 5 MB.
- **Allow Light:** o botão Allow Light da ferramenta de parede (Unofficial Patch) fica ligado até você desligar; toda parede desenhada com ele ligado deixa a luz passar. Se no Foundry todas as paredes de um andar vierem com Allow Light, o importador trata como engano e usa paredes normais.
- **Ordem dos andares:** no Dungeondraft a lista de andares vem de cima para baixo. O mod numera os arquivos de baixo para cima (`_1_` = térreo) e o importador já monta nessa ordem. Se algum mapa vier invertido, use **Inverter ordem** no importador.

## Se algo der errado

- Se a janela de exportação ficar com algo para fora (e por isso não der para clicar), feche e abra de novo: o mod aumenta a janela para caber tudo.
- Mensagens do mod aparecem no log do Dungeondraft com o prefixo **[NaurenFoundry]**.
- Se a moldura de alguma porta não for identificada, o importador usa a regra de antes (parte inteira do comprimento) — nada quebra.
- Mande o log (e, se puder, o `.dd2vtt`) que eu corrijo.
