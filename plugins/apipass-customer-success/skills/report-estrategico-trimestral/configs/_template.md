# Config de cliente — Report Estratégico Trimestral

Copie este arquivo para `configs/<cliente>.md` e preencha. O que não souber, **deixe marcado como `PENDENTE`** — a skill trata campo pendente como seção a declarar no fim do report, e nunca como valor a inventar.

Nada de tier, custo unitário ou valor de fatura aqui. Report estratégico não fala preço — isso é do `extrato-consumo`.
**Nenhuma credencial, token ou senha neste arquivo.**

---

## Identificação

| Campo | Valor | Observação |
|---|---|---|
| `account_name` | | resolve o realm no Keycloak **e** é o subdomínio da plataforma (`https://<account_name>.app.apipass.com.br`) |
| `nome_exibicao` | | como o cliente é chamado no corpo do report |
| `destinatarios` | | cargo e nome de quem recebe (gerente/coordenador). **Governa o tom**: quanto mais distante da operação, menos jargão técnico |

## Período

| Campo | Valor | Observação |
|---|---|---|
| `offset_utc` | `-03:00` | **não presuma −3**: se o horário de verão voltar, a janela muda e o número sai errado sem sinal de erro |
| `timezone` | `America/Sao_Paulo` | rótulo dos buckets |
| `calendario` | `civil` | `civil` (Q1=jan-mar) ou `fiscal` — se o cliente usa ano fiscal, registrar aqui o mês de início |

## Ambiente

| Campo | Valor | Observação |
|---|---|---|
| `projetos_internos` | | nomes **exatos** dos projetos a excluir da contagem (projetos da própria APIPASS, sandboxes internos). Nome errado = projeto contado a mais, silenciosamente |
| `plano_contratado` | `PENDENTE` | execuções/mês. Insumo da seção de oportunidades. Fonte: SharePoint (pasta do cliente) ou informado pela CS |

## Pacote contratado

A quota é **mensal**, e a tela filtra por mês/ano. Fica em **Gerenciamento de Conta → CONSUMO → Flow Engine**, acessível pelo **ícone de avatar** (o círculo à direita do nome, não o nome) no topo direito.

**Rota exata**, verificada em 19/08/2026: `https://<conta>.app.apipass.com.br/account-manager/usage-explorer/flow-engine` — e a aba Serviços é `/account-manager/usage-explorer/solution-services`. Rota inventada redireciona para a raiz sem erro, o que é fácil de confundir com falta de permissão: **use esta rota antes de concluir que o acesso está bloqueado.**

Mecânica da tela (Angular Material, não `<select>` nativo): `form_input` falha com `Element type "MAT-SELECT" is not a supported form input`. Clique o `mat-select`, clique a `mat-option` pelo texto do mês, e **só então** clique a lupa — em passo separado. Encadear seleção e busca na mesma chamada devolve o mês novo no rótulo com os números do mês anterior, silenciosamente. Confira sempre que o número mudou.

⚠️ **A aba Serviços tem bug de exibição** (visto na Conta B): quota do Sistema de Filas volta como `1` (gerando percentuais como `344380600%`) e o Object Store volta `NaN`. O **uso** parece legítimo; a **quota** não. Não levar percentual dessa aba ao report.

| Campo | Valor | Observação |
|---|---|---|
| `instancia` | | ex.: `micro` |
| `execucoes_contratadas_mes` | `PENDENTE` | **colete os 3 meses do trimestre.** Uma linha de referência única assume quota constante; se o plano mudou no meio do período, a linha mente |
| `trafego_contratado_mes` | `PENDENTE` | ex.: `100 GB` |

⚠️ **Essa tela pode retornar `/unauthorized`** para o usuário da CS numa conta de cliente — foi o caso da Conta A. Quando isso acontecer é **permissão a conceder, não URL a descobrir**.

🚫 **NÃO buscar o número por outro caminho.** A tela é a **única fonte aceita** para capacidade (regra da Elisama, 26/08/2026): *"você não pode acrescentar um dado que desconheci"*. Existe um endpoint publicado que devolve a mesma quota sem passar pela permissão de tela — usá-lo para preencher o report **foi reprovado**. Serve para diagnóstico interno, nunca para o documento.

Sem acesso: o tópico **não é preenchido**, o gráfico sai no padrão **sem nada escrito nele**, e o report **declara a falta de autorização em texto** — automático, em dois lugares, a partir de `semAcessoCapacidade` / `semAcessoCapacidadeCurto` do `rotulos-canonicos.json`. Registre aqui qual dos três casos é o desta conta: tela abre / `/unauthorized` / não consegui chegar à tela.

## Suporte — TABELA OBRIGATÓRIA, ticket a ticket

🔴 **Preencha na hora da coleta, com a coluna Serviço.** O Dashboard CS - Métricas Suporte **expurga tickets encerrados com mais de 3 meses** e o campo de data tem `min` — depois disso, **esta tabela é a única fonte do trimestre**. Não é conveniência de documentação: é o backup do dado.

Fonte e mecânica em `references/dashboard-suporte-movidesk.md`. Filtre **sempre por cliente**.

| Data | Chamado | Serviço | Status |
|---|---|---|---|
| | | | |

**Resumo que vai ao report** — quantidade e corte por serviço, **nunca tempo de resolução**:

| Campo | Valor |
|---|---|
| `chamados_total` | |
| `chamados_em_aberto` | |
| `chamados_por_servico` | ex.: `N1: 3 · Manutenção de Fluxo: 1 · Nova Feature: 1` |

- Custo já pago por não ter feito isso: a **Conta C** não tinha config, e o chamado de 13/05 do 2026Q2 é **perda definitiva**. A Conta A se salvou porque a tabela estava aqui desde 13/08.
- **Zero chamados não se aceita de primeira** — reabra a janela o quanto a retenção permitir. Zero confirmado é informação boa.

## Jira — atividades em andamento

Projeto **PIL ("Gestão de Projetos")**. Não existe campo de cliente: o recorte é por texto, montado a partir do `mapa_area_negocio` e dos `sistemas_conhecidos`.

| Campo | Valor |
|---|---|
| `jira_termos` | ex.: `"<cliente>" OR "<sistema core>" OR "<canais>"` |

- **Excluir sempre o projeto CONSOLE** — produto interno da APIPASS.
- **Nem todo card cita o nome do cliente.** Na Conta A, 1 de 13 dizia "[Conta A]"; os demais vinham pelo nome dos sistemas.
- **Status com 1 ou 2 cards: abra e leia.** Nunca inferir a fase pelo nome do status — use `statusCategory` (`new` = pendente, `indeterminate` = em andamento, `done` = concluído).

### Cards que NÃO vão ao report desta conta

| Card | O que é | Decisão |
|---|---|---|
| | | |

## Tradução para linguagem de gestor

`mapa_area_negocio` — dicionário de padrão-no-nome-do-fluxo → sistema integrado + área de negócio. É o que transforma lista de fluxos em "temos integração que atende logística, RH, financeiro", que foi o pedido explícito da Vanessa.

Preencher progressivamente: o que não casar entra na lista "a classificar" e é **perguntado**, nunca chutado. A partir do segundo trimestre o mapa já cobre quase tudo.

| Padrão no nome do fluxo | Sistema | Área de negócio |
|---|---|---|
| `ex.: *Protheus*` | Protheus | Financeiro |
| `ex.: *NF*`, `*Nota*` | — | Fiscal |

`sistemas_conhecidos` — lista dos sistemas que o cliente integra, para conferência: se a coleta trouxer um sistema fora desta lista, é sinal de ambiente novo no trimestre (informação boa para a seção de crescimento).

## Entrega

| Campo | Valor | Observação |
|---|---|---|
| `pasta_entrega` | `Downloads\CS\Reports Estratégicos\<cliente>\` | onde vão o .docx, o .pdf e o `snapshot-<AAAA>Q<N>.json` |
| `layout` | **B** (padrão para todo cliente, decidido em 19/08/2026 - não alterar sem pedido explicito) |
| `cor_destaque` | `#1F3864` | **hex oficial da marca ainda não confirmado** — este é um azul-marinho provisório, coerente com a identidade da plataforma. Confirmar com marketing antes da primeira entrega ao cliente |

## Histórico

| Trimestre | Snapshot | Report entregue em | Observação |
|---|---|---|---|
| | | | |

Sem snapshot do trimestre anterior não existe comparativo — a seção de crescimento vira "linha de base estabelecida neste trimestre", declarada como tal.
