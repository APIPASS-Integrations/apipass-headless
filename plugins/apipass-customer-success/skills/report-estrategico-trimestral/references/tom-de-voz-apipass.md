# Tom de voz APIPASS aplicado ao report

Fonte: `Downloads\CS\APIPASS - Manual tom de voz 2.pdf` ("Guia de linguagem e tom de voz", 2025). Este arquivo resume **só o que governa a redação do report**; o manual é a autoridade.

## Regra de grafia — a única inegociável

**APIPASS, em TODAS as maiúsculas.** O manual lista explicitamente como usos incorretos: `APIPass`, `Apipass`, `ApiPass`.

Vale para o corpo do report, o nome do arquivo e qualquer texto que chegue ao cliente. Confere com:

```bash
grep -o -E "APIPass|Apipass|ApiPass|APIPASS" word/document.xml | sort | uniq -c
```

## O tom: formalidade + empatia + objetividade

Palavras do manual: *"Nosso tom de voz será um equilíbrio entre formalidade, empatia e objetividade"*, para que a comunicação *"transmita autoridade e credibilidade, focando em entregar mensagens assertivas e bem fundamentadas, mas de forma humanizada e sem ruídos."*

Como isso cai em cada bloco do report:

| Componente | O que o manual pede | Como aplicar |
|---|---|---|
| **Formalidade** | tom profissional e respeitoso | sem gíria, sem exclamação, sem jargão interno da APIPASS no texto do cliente |
| **Empatia** | mostrar entendimento dos desafios do cliente | uma frase no resumo que nomeia o desafio real do setor dele ("integrar os sistemas de uma seguradora é um desafio de governança tanto quanto de tecnologia") |
| **Objetividade** | mensagem clara, sem ambiguidade, focada em soluções e benefícios | cada número com a leitura de negócio ao lado; oportunidade sempre com evidência + ganho |
| **Humanização** | o manual endossa expressões como *"vamos juntos"* | o bloco de fechamento (`fechamento` no JSON) |

**Sem ruídos ≠ sem má notícia.** "Assertivas e bem fundamentadas" impede maquiar dado. Na 1ª edição da Conta A as execuções caíram 9,1% e o texto diz isso na primeira linha da leitura — o tom entra em *como* se diz e no compromisso de apurar junto, não em esconder.

## Termos proibidos e seus substitutos

Regra da Elisama, 19/08/2026. Não é preferência de estilo — é vocabulário da casa.

| Nunca escrever | Sempre escrever |
|---|---|
| promover as integrações a produção · promoção para produção · promovê-las · levar ao ambiente produtivo · go-live | **publicar as integrações em produção** |

Na plataforma a ação se chama **publicar** (é o que o botão faz, e `PUBLICADOS` é o KPI do dashboard). "Promover" é jargão de pipeline de outra escola e não corresponde a nada que o cliente veja na tela.

Conferir antes de gerar:

```bash
grep -n -i -E "promo[vç]|ambiente produtivo|go-live" <dados>.json
```

## Vocabulário oficial

Termos que o manual manda usar para descrever produto e serviço: **iPaaS · Plataforma de Integração · Integração de Sistemas · Integração · Automação de processos · Gestão centralizada · API · Integração API**.

Usar de forma natural, não empilhada. No report da Conta A: "integração de sistemas" no resumo, "automação de processos" na leitura de valor, "gestão centralizada" no título da oportunidade de arquivamento, "plataforma de integração" no bloco de capacidade.

## Assinatura e princípio

Princípio da marca: **"Simplificando integrações, impulsionando resultados."** O manual reforça: *"Como sempre afirmamos, simplificamos integrações e impulsionamos resultados."*

No renderizador isso é o campo `assinatura`, impresso na cor de destaque no fim do documento. Padrão adotado: `APIPASS — simplificando integrações, impulsionando resultados.`

## Como queremos ser vistos

**Confiável · Líder de mercado · Tecnológica · Humana · Focada no cliente.**

Serve como checklist de revisão: se o report não reforça nenhum desses cinco, o texto ficou burocrático. O bloco de confiabilidade cobre "confiável"; oportunidades cobre "focada no cliente"; o fechamento cobre "humana".

## Público — casa com o do report

O ICP do manual são empresas de médio e grande porte (logística, indústria, varejo, agronegócio, finanças, sistemas S) com faturamento acima de R$ 100 milhões. Os interlocutores listados incluem **CEO, CIO, diretor de TI, gerente de TI, gerente de projetos, coordenador de TI, arquiteto de soluções**.

Isso confirma a premissa do report: o público é o decisor, e o `destinatarios` da config governa o nível de detalhe técnico. Quanto mais próximo de C-level, menos nome de fluxo e mais frente de negócio.

## Campos do JSON que existem por causa do manual

- `meta.marca` — a marca acima do título, em maiúsculas.
- `fechamento` — parágrafo humanizado de encerramento.
- `assinatura` — o princípio da marca.

## Pendente

O manual de tom de voz **não traz paleta de cores**. O `cor_destaque` segue provisório (`#1F3864`) — confirmar o hex oficial com marketing, provavelmente num manual de identidade visual separado.
