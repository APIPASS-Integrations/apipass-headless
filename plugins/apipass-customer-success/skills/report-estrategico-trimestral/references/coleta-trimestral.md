# Coleta trimestral no MCP da APIPASS — chamada a chamada

As regras de janela, truncamento e deduplicação **não foram descobertas aqui**: são herdadas de `../../extrato-consumo/references/mcp-coleta.md`, onde foram medidas contra dado real e conferidas com um extrato já entregue ao cliente. Este documento adapta aquelas regras do mês para o trimestre e acrescenta o que é específico do report.

## Autenticação

```
apipass_auth_status                    -> { authenticated, expiresInSeconds, realm }
apipass_login(account_name="<conta>")  -> { authorizeUrl }
```

- `account_name` resolve o **realm no Keycloak**. É o gancho de acesso ao ambiente do cliente.
- O login é OAuth: devolve uma URL que **alguém precisa abrir e autorizar**. Não existe caminho headless — a skill para e espera aqui.
- Token válido ~12h.
- `list_projects`, `list_flows` e `get_execution_summary` **não têm** parâmetro de conta: são escopados ao token. Logo, **um login por conta**; trocar de cliente exige novo login.

## Janela do trimestre — a armadilha nº 1

`startDate`/`endDate` são **instantes UTC**. O parâmetro `timezone` só governa como os buckets são rotulados, não como a janela é interpretada. **E `endDate` é inclusivo.**

```
startDate = <1º dia do 1º mês do trimestre>T03:00:00.000Z
endDate   = <1º dia do mês seguinte ao trimestre>T02:59:59.999Z
```

Fechar no primeiro instante do mês seguinte captura um resíduo do dia 1º. No extrato isso foi medido: em julho/2026 o resíduo era um bucket extra de 864 execuções, exatamente a diferença entre as duas janelas.

Exemplo resolvido (offset −03:00):

```
Q2/2026 (referência):  2026-04-01T03:00:00.000Z → 2026-07-01T02:59:59.999Z
Q1/2026 (baseline):    2026-01-01T03:00:00.000Z → 2026-04-01T02:59:59.999Z
```

**Não presuma −3.** O offset vem da config: se o horário de verão voltar, a janela muda e o número sai errado sem nenhum sinal de erro.

Diagnóstico na série `monthly`: o trimestre tem **exatamente 3 buckets**. Um quarto bucket, com valor pequeno, significa que o `endDate` invadiu o mês seguinte.

**Trimestre em curso nunca sai sem o rótulo de parcial** (`meta.parcial = true`). Um report trimestral com 40 dias de dado, apresentado como fechado, é pior que report nenhum.

## Chamadas

### Execuções agregadas — referência e baseline
```
get_usage_summary(metric="total", startDate, endDate, timezone)
  -> { requests, executions }
```
Duas vezes: uma na janela do trimestre, outra na do trimestre anterior. **As execuções do baseline são recalculáveis a qualquer momento** — não dependem de snapshot, porque o dado é estável (comprovado no extrato: junho/2026 reproduz exato).

### Série mensal — o gráfico de crescimento
```
get_execution_summary(period="monthly", startDate, endDate, timezone)
  -> 3 buckets no trimestre
```

### Projetos
```
list_projects(pageSize=100, archived="active")
  -> { data: [ { id, name, accountId, lastUpdate, info: { flowsAmount }, archived } ], totalItems }
```
- Paginado, `page` 1-based. Itere até cobrir `totalItems`.
- O default do parâmetro `archived` já é "ativos"; ser explícito documenta a intenção.
- Excluir os `projetos_internos` da config **pelo nome exato**. Nome errado = projeto contado a mais, silenciosamente.
- **Não existe data de criação** no objeto de projeto — confirmado na `conta-a` em 05/08/2026. Os campos são `id`, `name`, `accountId`, `lastUpdate`, `info.flowsAmount`, `documentationOasAccessType`, `archived`, `tagIds`. Logo, "quantos projetos existiam no trimestre passado" **só sai do snapshot**.
- **`info.flowsAmount` inclui arquivados.** No projeto POC da `conta-a` ele diz 12, e `list_flows` com `archived="active"` devolve 10. A contagem autoritativa de integrações ativas é o `totalItems` do `list_flows`, nunca o `flowsAmount`.

### Fluxos
```
list_flows(projectId, pageSize=100, archived="active")
  -> { data: [...], totalItems }
```
`projectId` é **obrigatório** no contrato da ferramenta — não existe "listar todos os fluxos da conta". Itere os projetos.

> **Verificado na `conta-a` em 05/08/2026: o objeto de fluxo NÃO traz data de criação.** Os campos são `id`, `name`, `parent`, `lastUpdate`, `info.stepsAmount`, `info.stepsImage`, `info.description`, `archived`, `tagIds`, `lastUpdateInfo` (com `userName` e `date`).
>
> Consequência que não tem contorno: **não é possível saber o que foi criado no trimestre.** `lastUpdate` é atualização — um fluxo de 2023 editado em junho apareceria como "novo". Portanto o campo `novos` do JSON fica **vazio na primeira edição**, e o report declara em texto que a linha de base de ambiente foi estabelecida ali. Não preencher `novos` por inferência de `lastUpdate`.

**Truque para contar sem gastar contexto:** o payload completo do `list_flows` é enorme (o `stepsImage` de um fluxo com 95 passos traz 95 URLs). Quando só a contagem interessa, chame com `pageSize=1` — `totalItems` vem correto com uma única linha de dado.

### Execuções por fluxo
```
get_execution_summary(period="flow", projectId, startDate, endDate, timezone)
  -> [ { flowId, flowName, projectId, projectName, stageName, requests, executions, throughput } ]
```

1. **Sempre com `projectId`.** Sem ele, na conta inteira a resposta estoura o limite do MCP e volta **truncada no meio de um registro**, sem erro de parsing. Medido no extrato em junho/2026: perdeu 8.670 execuções, porque as linhas cortadas eram fluxos agendados com `requests = 0` e volume alto — exatamente o que fica no fim da resposta.

2. **NÃO deduplique por `flowId` + `stageName`. Some tudo.**

   > **Correção de uma regra herdada.** O `../../extrato-consumo/references/mcp-coleta.md` manda deduplicar, "ou o total infla". **Na conta `conta-a`, Q2/2026, isso está errado e subnotifica.** Medido em 05/08/2026 sobre 95 linhas em 10 projetos:
   >
   > | | execuções |
   > |---|---|
   > | `get_usage_summary` | 30.800 |
   > | soma de todas as linhas, sem dedupe | **30.800** ✓ |
   > | soma com dedupe por `flowId`+`stageName` | 30.512 ✗ (−288) |
   >
   > O motivo: quando o mesmo subfluxo é chamado a partir de projetos diferentes, os pares `flowId|stageName` repetidos **não são cópias do mesmo número — são fatias diferentes**. Exemplos reais: `master-rest-gera-token|qas` devolve 71 sob o projeto CORE e 81 sob RURAL; `master-rest-...-cria-proposta-transportes|qas` devolve 19 sob CORE e 38 sob TRANSPORTES. Deduplicar joga uma das fatias no lixo.
   >
   > **O árbitro é sempre o teste de consistência, nunca a regra.** Rode as duas somas e fique com a que reproduz o `get_usage_summary`. Se nenhuma reproduzir, pare — é a janela que está errada.

3. **Uma linha é um par fluxo × stage**, não um fluxo.

4. **`stageName` não é só `Prod`/`Dev`.** Na `conta-a` há **três** valores, em minúsculas: `prod`, `qas`, `dev`. Não faça `-eq "Prod"` nem presuma duas trilhas; agregue por qualquer valor que vier.

5. **Não confie no `projectName` que vem nas linhas.** Ele divergiu do `list_projects` em dois dos dez projetos: consultando o projeto `GATEWAY > CORE - CORE` as linhas voltam rotuladas `GATEWAY > CORE`, e as do projeto `- INTERNAL` voltam rotuladas `- CORE`. Use o nome do `list_projects`, indexado pelo `projectId` que **você** consultou.

6. **A atribuição fluxo→projeto do endpoint de uso não é a do `list_flows`.** O projeto POC devolveu `[]`, mas o fluxo `[DEMO] Testes Unitários` — que é filho de POC — apareceu com execuções sob o projeto CORE. Para "quais integrações rodaram", agregue por `flowId`; para "de quem é o projeto", use o `parent` do `list_flows`.

### Confiabilidade — colete sempre
```
get_execution_summary(period="daily", startDate, endDate, timezone)
  -> [ { date, totalExecutions, totalRequests, totalExecutionsWithError, ... } ]
```
Agregue no trimestre: taxa de sucesso = 1 − (erros ÷ total).

**É tópico fixo do report (o 6 dos 8) desde 19/08/2026** — nasceu como bloco candidato, entrou nos três reports do 2026Q2 a pedido da Elisama, e a **validação formal da Vanessa segue pendente**. Colete sempre.

E cuidado com a fronteira: isto é confiabilidade **agregada da conta**, não "uptime de fluxos críticos" — esse último está fora de escopo porque exige um critério de criticidade que não existe. **Não ranquear fluxo por criticidade aqui.**

⚠️ **Não repetir no texto deste tópico a decomposição erro/sucesso** que o tópico 2 é obrigado a trazer. Foi uma das repetições que estourou o limite de 2 páginas na Conta A.

### `totalExecutionsWithError` nos DOIS trimestres — obrigatório

Colete o erro **também no trimestre de baseline**, não só no atual. Sem ele a decomposição obrigatória de queda de execuções (`references/estrutura-report.md` §2.2) não existe, e a seção de crescimento sai afirmando queda de uso onde pode não haver nenhuma.

Semântica verificada em 13/08/2026 — detalhe em `../../../projects/.../memory` ou resumido aqui:

| status do log | `totalExecutions` | `totalExecutionsWithError` |
|---|---|---|
| `OK` | 1 | 0 |
| `ERROR` | 1 | 1 |
| `STOPPED` | 1 | 1 |

Todo desfecho que não é sucesso cai no lado do erro. Logo **`total − comErro` = concluídas com sucesso, exato**, sem resíduo de `RUNNING`/`STOPPED`.

### Limites do log de execução

- **`list_flow_execution_logs` exige `startDate`** — sem ele, HTTP 400.
- **A retenção não alcança 5 meses.** Consulta de março/2026 voltou vazia em agosto/2026, para todos os status. A **série agregada continua devolvendo** o mês normalmente.
- Consequência: métrica agregada é auditável a qualquer momento; **execução individual antiga, não**. Se o cliente pedir o detalhe dos erros de um mês passado, o caminho é a série agregada.
- Registros trazem `executionMode` (`DEFAULT`/`TEST`) — **execução de teste conta no summary**.

### Subfluxo contribui ZERO execução

Fluxo com trigger de subfluxo tem `stepsImage[0] = "CHILD_FLOW"` no `list_flows`, e o log dele traz `summary.totalExecutions: 0` com requisições e tráfego normais. A execução é contada no **master** que o chamou.

É o que explica `fluxosComTrafego` > `fluxosComExecucao` e um subfluxo aparecer com centenas de MB e zero execução. **Nunca apresentar isso como desperdício ou ociosidade** — não é anomalia, é contabilização.

## Teste de consistência — rodar sempre antes de renderizar

Os três endpoints concordam entre si:

```
get_usage_summary.executions  ==  soma da série monthly  ==  soma das linhas flow
```

⚠️ **Sem dedupe.** Uma versão anterior desta linha dizia "após dedupe", contradizendo o bloco de correção logo acima nesta mesma referência. **Rode as duas somas** — direta e com dedupe por `flowId`+`stageName`— e **fique com a que reproduz o `get_usage_summary`**. Medido nas três contas do 2026Q2, a direta reproduz exato: Conta A 30.800, Conta B 18.175, Conta C 40.438. Se **nenhuma** reproduzir, é a **janela** que está errada.

Se não bater, **é erro de parâmetro, não flutuação do dado**. Pare e investigue a janela antes de gerar qualquer documento — foi assim que a divergência do extrato acabou sendo explicada.

> **O teste de consistência é o árbitro, acima de qualquer regra herdada.** Foi ele que derrubou a regra de dedupe do `extrato-consumo`. Não confie na regra porque está escrita; confie no número que fecha.

## Derivações — o que transforma dado em report

### Sistema integrado e área de negócio
Aplique o `mapa_area_negocio` da config sobre os nomes de projeto e fluxo. O que não casar entra em `ambiente.aClassificar` e é **perguntado**, nunca chutado — o script já emite pendência quando essa lista vem preenchida.

Isto é o pedido explícito da Vanessa: não é a lista de fluxos, é "temos integração que atende logística, temos integração que atende RH, temos integração que atende financeiro".

### Oportunidades
- Fluxos nomeados `teste*`, `temp*`, `copia*` ou com nome de pessoa → oportunidade de **arquivamento** (funcionalidade já disponível, despolui a tela de projetos).
- Áreas de negócio **sem** integração → frente de expansão, enquadrada como capacidade disponível.
- Roadmap de produto: carregue `/apipass-customer-success:roadmap-presentation` para o conteúdo (Jira PD/Polaris).

**Enquadramento obrigatório:** nunca "contratou X, usa Y" como sobra ociosa. Risco levantado pela própria Vanessa — o cliente conclui que deve *reduzir* o plano. É sempre capacidade para crescer e features que ele já pode usar.

## Snapshot

Ao final da coleta, grave `<pasta_entrega>/snapshot-<AAAA>Q<N>.json`:

```json
{
  "cliente": "conta-a", "trimestre": "2026Q2",
  "janela": { "startDate": "...", "endDate": "...", "timezone": "America/Sao_Paulo" },
  "geradoEm": "2026-08-05",
  "projetosAtivos": 0, "fluxosAtivos": 0, "fluxosProd": 0, "fluxosDev": 0,
  "execucoesTrimestre": 0,
  "sistemas": [], "areasNegocio": [],
  "inventario": [ { "projeto": "", "fluxo": "", "stage": "", "sistema": "", "area": "" } ],
  "pendencias": []
}
```

Por que o snapshot existe, apesar de execuções serem recalculáveis: **contagem de projetos/fluxos ativos é fotografia** e não se reconstrói para trás. Sem ele, o comparativo da seção de crescimento nunca começa a existir.

Sem snapshot anterior, a seção vira "linha de base estabelecida neste trimestre" — declarada como tal, sem número inventado.
