# apipass-customer-success

Skills de Customer Success da APIPASS para Claude Code. Leem o ambiente pela plataforma
(MCP) e entregam o material pronto para revisão humana — nunca para envio direto ao cliente.

| Skill | O que faz |
|---|---|
| `report-estrategico-trimestral` | Report de 1-2 páginas para o **gestor do cliente**: visão do ambiente, capacidade, suporte, confiabilidade e oportunidades. Gera `.docx` e PDF, e grava o snapshot do trimestre. |
| `extrato-consumo` | Extrato mensal de consumo para cliente de faturamento por execução: coleta, calcula tier e faturamento, monta o deck. |
| `analise-risco-churn` | Classifica contas por faixa de acesso, cruza com adoção, criação recente e inadimplência, e devolve lista priorizada com os critérios que pesaram. |

## Contas dos exemplos são anonimizadas

As referências documentam cada regra **com o caso real que a originou** — é o que faz a
regra ser verificável em vez de norma abstrata. Como este repositório é público, as contas
aparecem sob rótulo neutro:

| Rótulo | Natureza da conta |
|---|---|
| **Conta A** (`conta-a`) | seguradora; integra o core de apólices aos canais de corretoras |
| **Conta B** (`conta-b`) | comércio exterior; modelo OEM — o produto dela é integrado ao ERP dos clientes dela |
| **Conta C** (`conta-c`) | recebimento fiscal; NF-e por e-mail e vínculo de carga no ERP |
| **Conta D** | faturamento por consumo, com tabela de tiers e reajuste contratual |
| **Cliente X/Y/Z** | contas de terceiros que apareceram em recorte mal filtrado |

Os **números** dos exemplos são reais e foram preservados, porque é deles que a lição
depende (ex.: a soma direta reproduz `30.800` e a deduplicada erra por `288`). Sem o nome
da conta, não são atribuíveis.

## Configs de cliente ficam fora deste repositório

Cada skill traz apenas `configs/_template.md`. As configs preenchidas — que carregam
execuções, quotas contratadas, tabelas de chamados e IDs de projeto — são **dado de
cliente**, não código, e vivem no ambiente de quem opera a skill. Uma vez em repositório
público, sairiam do controle de quem publicou.

## Requisitos de ambiente

O `report-estrategico-trimestral` e o `extrato-consumo` geram documento com **automação COM
do Office** via PowerShell (`Word.Application` / `PowerPoint.Application`), o que hoje
restringe esses dois a **Windows**. A `analise-risco-churn` não tem essa dependência.

Detalhes, armadilhas medidas e o que **não** entra em cada documento estão nas
`references/` de cada skill.
