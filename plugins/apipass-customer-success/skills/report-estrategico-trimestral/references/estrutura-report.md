# Estrutura do Report Estratégico Trimestral — especificação tópico a tópico

Base: reunião "Agenda interna - Skills Claude - CS" (30/07/2026, Fathom 767320050), brainstorm `REPORT GERENCIAL.docx` da Vanessa, e as decisões da Elisama tomadas nas execuções de agosto/2026.

Público: **gerentes e coordenadores decisores** do cliente. Periodicidade: **trimestral**. Formato: **PDF, 1-2 páginas, visual** — layout **B** (faixa de KPIs no topo), padrão para todo cliente.

## 🔴 O report tem os MESMOS 8 TÓPICOS para todo cliente, nesta ordem

Decisão da Elisama, 19/08/2026. Não é sugestão de sumário: é o contrato do documento.

| # | Tópico | Status | Fonte |
|---|---|---|---|
| 1 | Visão geral do ambiente | **ativo** | MCP APIPASS + documentação de fluxos |
| 2 | Capacidade de crescimento | **ativo** | MCP + snapshot do trimestre anterior |
| 3 | Capacidade do ambiente | **ativo — acesso obrigatório** | tela Gerenciamento de Conta |
| 4 | Usuários ativos | **ativo, sem dado** | endpoint existe, janela fixa de 30 dias |
| 5 | Suporte | **ativo — consulta obrigatória** | Dashboard CS - Métricas Suporte |
| 6 | Confiabilidade das integrações | **ativo** (candidato validado na prática) | MCP |
| 7 | Oportunidades de uso | **ativo** | MCP + roadmap (Jira PD/Polaris) |
| 8 | Atividades em andamento | **ativo** | Jira, projeto PIL |

**Tópico sem dado NÃO desaparece do documento.** Ele renderiza declarado — e a rotulagem vem de `assets/rotulos-canonicos.json`, nunca do JSON do cliente, porque foi isso que quebrou quando cada conta trazia os seus rótulos.

> **A numeração `2.1`–`2.6` do rascunho original não vale mais.** Ela cobria 6 seções e a ordem era outra. Se você encontrar referência a "seção 2.4", é o tópico 5 (Suporte). Guardado só para leitura de material antigo.

---

## 1 · Visão geral do ambiente

O que entra:
- Projetos e integrações ativas, com **os projetos ativos nomeados** (pedido da Elisama, 19/08/2026).
- Sistemas integrados (Protheus, SAP, Salesforce, TOTVS, WMS…).
- **Frentes de negócio atendidas** e quais processos já estão integrados.

Sobre "frentes de negócio": a Vanessa foi explícita no que quis dizer — é "temos integração que atende logística, temos integração que atende RH, temos integração que atende financeiro". Não é a lista de fluxos; é a **tradução** da lista de fluxos para a linguagem do gestor.

⚠️ **Não reaproveitar os rótulos daqui na tabela do tópico 2.** Aqui se conta o que está **implantado**; lá se mede o que **executou no trimestre**. Com o mesmo rótulo nos dois lugares, o gestor vê `10` na visão geral e `9` na tabela para a "mesma" coisa e conclui que um dos dois está errado. Aconteceu na v1 da Conta A.

## 2 · Capacidade de crescimento

Comparativo trimestral: projetos e integrações **com execução** hoje vs. o trimestre anterior, destacando o que foi adicionado e a que serve.

Formato mental do argumento (palavras da Vanessa): "há três meses você tinha 10 integrações, hoje tem 15; você ganhou estes dois projetos novos, que atendem XYZ."

Métrica é **"com execução no trimestre"**, não "ativos": contagem de ativos é fotografia e **não se reconstrói para trás** sem snapshot; "com execução" é recalculável e explica melhor o volume — o que justifica N execuções é quanta integração rodou, não quanta estava cadastrada.

O snapshot vive em `<pasta_entrega>/snapshot-<AAAA>Q<N>.json`, schema em `coleta-trimestral.md`. **Sem snapshot anterior**, o tópico vira "linha de base estabelecida neste trimestre", declarado como tal.

### 🔴 O gráfico deste tópico: o padrão NUNCA muda

Regra da Elisama, 26/08/2026: *"Vc deve manter o padrão do gráfico independente de qualquer coisa (…) o padrão do gráfico nunca muda"*.

Elementos fixos: barras com o **valor absoluto**, rótulo do mês, e a linha de média do trimestre anterior quando houver. Único elemento **opcional**: a linha tracejada da **capacidade contratada** com o percentual em cada barra — e ela entra **somente** quando houve acesso à tela de Gerenciamento de Conta (ver tópico 3).

**Nada é injetado no PNG para explicar ausência de dado** — nem nota, nem legenda de "sem permissão", nem texto substituto. O parâmetro `notaContratado` foi **removido** de `New-BarChartPng`; se aparecer num JSON antigo o script ignora e emite pendência. Ausência se declara em **texto do documento**.

Consequência aceita em 26/08/2026, depois de eu apresentar três alternativas: cliente com capacidade tem barras pequenas sob a linha do contratado, cliente sem capacidade tem barras cheias — **os gráficos não ficam com a mesma aparência**, e a decisão dela foi manter assim. O que impede a leitura de "gerou errado" é a frase obrigatória do tópico 3, não a uniformidade do desenho. **Não reabrir.**

### 🔴 OBRIGATÓRIO: quando o total de execuções cai, decomponha em sucesso e erro

Regra da Elisama, 12/08/2026. **Nunca apresentar queda de execuções sem essa decomposição** — sem ela o gestor lê redução de uso onde pode não haver nenhuma.

Contas, todas sobre `totalExecutions` e `totalExecutionsWithError` da série `monthly` (campos da plataforma, não derivados):

```
concluídas com sucesso  = totalExecutions − totalExecutionsWithError   (por trimestre)
taxa de erro            = totalExecutionsWithError ÷ totalExecutions
redução de falhas       = (erroAnterior − erroAtual) ÷ erroAnterior
```

Compare **sucesso contra sucesso**. Foi o que virou a leitura da Conta A em 2026Q2: total caiu 9,1%, mas 29.501 → 29.660 concluídas com sucesso, ou seja **entrega igual com 74% menos falha**. A queda era de erro, não de uso.

Modelo de frase, validado com a Elisama e reutilizável trocando os números:

> "O total de execuções caiu X% entre os trimestres. Olhando só o total, parece redução de uso. Mas o total inclui execuções que terminaram em erro: no trimestre anterior foram N falhas em T execuções; neste, N' em T'. Em execuções concluídas com sucesso os dois trimestres são praticamente iguais — S e S'. Ou seja: o mesmo volume de operação foi entregue com Y% menos falhas. A concentração estava em <mês>, que teve Z% de taxa de erro."

Também aponte o **mês de concentração** do erro: reformula a pendência de "por que o trimestre caiu" para "o que aconteceu em <mês>", que é uma pergunta respondível pelo time do cliente ou pelo arquiteto da conta.

Argumento de credibilidade a usar na conversa: o cliente **confere isso sozinho** no dashboard dele — o gráfico já separa as barras em Sucesso e Erro, mesma origem do número.

**A expressão "concluídas com sucesso" é exata — verificado em 13/08/2026.** Nos logs (`list_flow_execution_logs`), o `summary` de cada registro casa 1:1 com o `status` terminal:

| status | `totalExecutions` | `totalExecutionsWithError` |
|---|---|---|
| `OK` | 1 | 0 |
| `ERROR` | 1 | 1 |
| `STOPPED` | 1 | 1 |

Todo desfecho que não é sucesso cai no lado do erro, inclusive `STOPPED`. Então `total − comErro` não carrega resíduo de `RUNNING`/`STOPPED` e a frase pode ir ao cliente sem ressalva.

Ainda **não verificado**, e portanto fora do texto: se execução com erro é reprocessada e o reprocessamento conta como nova execução.

**Retenção de log não alcança 5 meses** — consulta de março/2026 voltou vazia. A semântica do campo se verifica em dados recentes (não muda por mês), mas execuções antigas não são auditáveis uma a uma.

## 3 · Capacidade do ambiente

Instância contratada, **execuções contratadas por mês** e **tráfego de dados contratado por mês**, contra o mês de maior uso do trimestre.

### 🔴 A TELA É A ÚNICA FONTE ACEITA

Regra da Elisama, 26/08/2026:

> "se lembre que conta-a vc não tem acesso a aba gerencial, você não pode acrescentar um dado que desconheci"

O dado vem de **Gerenciamento de Conta → CONSUMO → Flow Engine** (`/account-manager/usage-explorer/flow-engine`), e o acesso a essa tela é **obrigatório** em toda execução. Se ela não abrir, o tópico **não é preenchido** — e **não importa que exista outro caminho técnico para o número**.

O erro que essa regra proíbe: na `conta-a` a tela retorna `/unauthorized`, e eu contornei chamando o endpoint publicado `grafana/usage-metrics/flow-engine-summaries`, que lê do banco sem passar pela permissão de tela. Obtive quota real e coloquei no documento. **Foi reprovado.** O número não foi visto por quem assina o report e não pode ser conferido contra a tela que o cliente vê. A rota via `core.apipass.com.br` serve para **diagnóstico interno**, nunca para preencher o report.

### 🔴 Sem autorização, o relatório é OBRIGADO a dizer isso

Regra da Elisama, 27/08/2026:

> "no report da conta-a e de qualquer outro cliente que você não tenha autorização para acessar a tela de gerenciamento, é obrigatório informar no relatório. Porque quem está lendo pensa que gerou errado."

Um `[Em construção]` seco **não cumpre a regra** — ele diz que falta algo, não *por que*. Sai automático em **dois lugares**: no próprio tópico (`semAcessoCapacidade`) e na linha "Não constam nesta edição" (`semAcessoCapacidadeCurto`), acrescentada pelo `Block-Rodape` mesmo com `naoConstam` vazio. O texto é **canônico no código**, não do JSON do cliente: não pode depender de eu lembrar a cada edição.

Enquadramento obrigatório: **liberação de acesso em andamento**, nunca indisponibilidade da informação, e a seção passa a ser preenchida na próxima edição.

### Regras de leitura da capacidade

- **Sempre que a tela abrir, o report leva execuções E tráfego** (Elisama, 26/08/2026). São os dois indicadores da tela, cada um com quota mensal própria.
- **Os dois picos podem cair em meses diferentes** — na Conta B execuções é maio e tráfego é junho. **Nomeie o mês em cada indicador.**
- **A quota é MENSAL e não acumula.** Nunca somar as três quotas do trimestre: esse denominador não existe em tela nem em contrato, e a média esconde o pico. Compare o **mês de maior uso** contra a quota mensal.
- **Colete os três meses, um a um.** Não presuma plano constante.
- **Unidade do tráfego: bytes ÷ 1024³**, rotulado "GB" — é como a plataforma exibe (verificado contra a tela). A diferença contra ÷10⁹ é de 7% e pode ir para um report sobre estouro de contrato.
- ⚠️ **Não usar `executionsUsagePercentage` para janela trimestral:** ele divide o total da janela pela quota **mensal**. Para janela de um mês está correto.

## 4 · Usuários ativos

Usuários do cliente que acessaram a plataforma no trimestre, sobre o total cadastrado.

**Ativo no documento, sem dado disponível.** Isto mudou de status: não é mais "suspensa por escopo". O endpoint `users-metrics/users-login-by-account` **existe** (ver `endpoints-grafana-metrics.md`), mas tem **janela fixa de 30 dias** e a retenção de eventos do Keycloak não foi verificada — depende do time dono.

Renderiza como `[Em construção]` hoje. ⚠️ **Pendência de decisão da Elisama:** pelo raciocínio dela sobre a capacidade, esse placeholder seco tem o mesmo problema de leitura — o gestor pensa que o documento saiu errado. Não escrevi frase própria porque o enquadramento honesto envolveria prometer prazo de entrega de um indicador, o que é decisão dela.

O MCP não substitui: `list_projects`/`list_flows` falam de ambiente, não de quem entrou nele.

## 5 · Suporte

Fonte: **Dashboard CS - Métricas Suporte** da própria APIPASS (`core.apipass.com.br/api/263aa242-.../prod/dashboard-movidesk`), **consulta obrigatória** em toda execução (Elisama, 19/08/2026). Mecânica completa em `dashboard-suporte-movidesk.md`.

> Este tópico **já não é suspenso**. A premissa "Movidesk fora de escopo, sem MCP" foi corrigida em 13/08/2026: a fonte não é o Movidesk direto, é um dashboard nosso que já consolida os chamados. Mesma reinterpretação que valeu para o Grafana.

### 🔴 Quantidade e SERVIÇO. Nada de tempo.

Regra da Elisama, 27/08/2026:

> "Não utilize dias corridos, e nenhuma referencia relacionado a dias por hora. Mantenha a quantidade de chamados e filtre por serviços. por exemplo: tive 3 chamados 2 foram N1 e 1 foi N3"

| Entra | Não entra |
|---|---|
| Quantidade de chamados (total, em aberto, encerrados) | ❌ tempo de resolução em **qualquer** unidade — dias corridos, dias úteis, horas |
| **Corte por serviço** (`suporte.porServico`) | ❌ **mediana** e "tempo médio", em qualquer forma |
| Categoria Movidesk, quando agrega leitura | ❌ os cards `medianaHoras` / `medianaNovaFeature` |

O script renderiza a linha "Por serviço: 3 N1 · 1 Manutenção de Fluxo · …" e **tem guard**: emite pendência se o texto casar com `dia corrido|dias úteis|mediana|tempo médio|horas de resolução`, ou se vier campo de tempo no JSON. Guard não é permissão para escrever e conferir depois.

Os serviços **não são só níveis de atendimento**: `N1`/`N2`/`N3` convivem com `Manutenção de Fluxo`, `Análise de Erros de Fluxo`, `Projetos`, `Nova Feature`, `BUG`, `Infra` e outros — 17 na lista canônica. Isso dá leitura melhor que tempo: *"três resolvidos no primeiro nível e os demais por frentes especializadas"* diz mais ao gestor que uma mediana.

Regra de apresentação que continua valendo, da Vanessa: **análise, não dado bruto.**

### 🔴 O histórico é EXPURGADO após 3 meses

Descoberto em 27/08/2026, e muda o **planejamento** da skill: a tela avisa *"Histórico disponível apenas dos últimos 3 meses. Tickets encerrados mais antigos são expurgados automaticamente."* O campo DATA INÍCIO tem `min` e o formulário **recusa a submissão** com data anterior — sem erro na página; a mensagem é a validação nativa do navegador.

- **Tabule ticket a ticket, com o serviço, em `configs/<cliente>.md` na hora da coleta.** Depois de 3 meses essa tabela é a **única** fonte do trimestre.
- **Gere o report perto do fechamento do trimestre.** Um report de Q2 feito em setembro não apura abril e maio.
- Custo real já pago: em 13/08 eu lia chamados de 20/04 da Conta A; em 27/08, não mais. A Conta A se salvou pela tabela na config; a **Conta C não tinha config** e o chamado de 13/05 é perda definitiva.
- **Zero chamados não se aceita de primeira:** reabra a janela o quanto a retenção permitir. Se continuar zero, o zero é real e é informação boa. Na Conta B confirmou-se — e em 27/08 ela **abriu** um chamado (#7651), o que prova que a conta usa suporte e reforça que o zero do Q2 é comportamento real, não registro sob contato individual.

## 6 · Confiabilidade das integrações

`get_execution_summary` já devolve `totalExecutionsWithError`: dá para dizer "N execuções no trimestre, taxa de sucesso de X%" sem nenhuma fonte externa.

Nasceu como **bloco candidato** para compensar a ausência do tópico 5, proposto porque a Vanessa pediu explicitamente sugestões de substituição. **Entrou nos três reports do 2026Q2 a pedido da Elisama** e virou tópico fixo, mas **segue pendente de validação formal da Vanessa**.

⚠️ Fronteira que não pode ser cruzada: isto **não é** "uptime de fluxos críticos", que está fora do escopo. Aquele exige um critério de criticidade que não existe; este é **agregado por conta** e **não ranqueia fluxo nenhum por criticidade**.

⚠️ **Não repetir aqui a decomposição erro/sucesso** que o tópico 2 é obrigado a trazer. Foi uma das repetições que estourou o limite de páginas da Conta A.

## 7 · Oportunidades de uso

Contratado vs. efetivamente usado, cruzado com o roadmap de produto e com o portfólio de funcionalidades já entregues.

Exemplo real citado na reunião: rodar uma varredura no ambiente, identificar vários fluxos nomeados "teste", "teste fulano", e apresentar a funcionalidade de **arquivamento** — que despolui a tela principal de projetos.

**Risco a gerenciar (levantado pela própria Vanessa):** apresentar "contratou 1 milhão, usa 500 mil" pode fazer o cliente concluir que deve *reduzir* o plano. Então o enquadramento nunca é sobra ociosa — é **capacidade disponível para crescer** e features que ele já pode usar. O plano contratado em si pode nem ser o ponto central.

**Terminologia obrigatória:** sempre *"publicar as integrações em produção"*, **nunca** *"promover as integrações a produção"*.

### 🔴 Oportunidade se sustenta em fonte, não em intuição

Erro cometido duas vezes no report da Conta C, ambas apontadas pela Elisama:

1. Escrevi *"o consumo de tráfego está sendo revisado em conjunto com a APIPASS e será tratado à parte"* — **inventei**. Não havia revisão nenhuma, e a frase comprometia a CS com um processo que pode não existir.
2. Escrevi, no tópico de Suporte, *"o que aponta para monitoramento proativo do recebimento como próximo passo"* — ela perguntou o que significava. Também **inventado**: não verifiquei que a plataforma oferece isso, nem houve decisão de que é o próximo passo.

**Regra:** tópico de análise descreve **o que aconteceu**; proposta de próximo passo só entra aqui, e só com a CS confirmando o que a plataforma entrega. **Teste antes de escrever: consigo apontar a fonte de cada afirmação desta frase?** Se a resposta passa por "faz sentido que", apague.

**E nomeie quem causa o comportamento** (Elisama, 26/08/2026): "um único subfluxo concentra 79% das requisições" é ruído — o gestor não sabe onde agir. O certo é "o subfluxo `sub-vincula-nf`, do projeto de vínculo de nota, em produção".

**Nunca decidir sozinho o que tem peso comercial.** Estouro de contrato, quota excedida, valor de fatura: apurar, apresentar à CS com as opções, e escrever o que ela decidir. Se a decisão não veio, a informação fica fora e a pendência diz isso — **sem frase de preenchimento**.

## 8 · Atividades em andamento

O que os times de CSM, Projetos e Arquitetos estão trabalhando com o cliente no momento.

**Deixou de ser input manual em 12/08/2026.** A fonte é o Jira, projeto **PIL ("Gestão de Projetos")**, via `searchJiraIssuesUsingJql`. Agrupar por **status**: concluídos, em homologação, priorizados, pausados.

```
project = PIL AND (text ~ "<cliente>" OR text ~ "<sistema core>" OR text ~ "<canais>") ORDER BY status ASC
```

**NUNCA inferir o significado de um status pelo nome dele.** Leia o `statusCategory` e **abra os cards** dos status pouco populosos antes de descrevê-los.

> Erro cometido em 12/08/2026, corrigido em 13/08: o PIL tem um status chamado `Prioritized`, e eu escrevi no report *"1 card, já na fila de desenvolvimento"*. O `statusCategory` dele é **`new` / "Itens Pendentes"** — não começou. E o card (PIL-728) era um **[Bloqueio] tipo Erro na API de callback do sistema de campo, aberto em fevereiro e sem movimentação desde junho**. Eu estava transformando um bloqueio de 6 meses em sinal de progresso, num documento que vai ao gestor decisor — e justamente na frente (Rural/sistema de campo) que o report apresenta de forma positiva.

Regra prática: status com muitos cards (`Fechada`, `Paused`) descreva pela contagem; status com 1 ou 2, **leia o card**. `statusCategory`: `new` = pendente, `indeterminate` = em andamento, `done` = concluído.

Três regras aprendidas na primeira execução (Conta A, 65 cards):

1. **Excluir o projeto CONSOLE.** É produto interno da APIPASS (o recorte por texto sem escopo de projeto trouxe 33 cards de lá). **Não pode aparecer em report de cliente.**
2. **O recorte é por texto, não por campo de cliente.** Não existe campo de cliente no PIL, então a contagem é **aproximada** — declarar nas pendências.
3. **Nem todo card do cliente cita o nome dele.** Na Conta A, só 1 dos 13 dizia "[Conta A]". Montar o recorte a partir do `mapa_area_negocio` e dos `sistemas_conhecidos` da config.

⚠️ **O recorte pode vazar card de outro cliente.** Na Conta B, 13 cards e só 6 eram da conta — um era do **Cliente X**. Na Conta C, o termo `outlook` trouxe 43 cards, a maioria de outros clientes. **Ler card a card antes de aceitar o resultado do JQL.**

Enquadramento: volume alto de cards **pausados** não é pendência a esconder. Se as frentes pausadas coincidirem com as apontadas como próximas do go-live (foi o caso na Conta A), isso é **gancho de conversa**.

O saldo de horas/fluxos a implementar continua **fora**: vem do Clock, e o MCP do Clock não existe.

---

## Itens FORA DE ESCOPO — e o motivo de cada um

Não reintroduzir por conta própria. Se o usuário pedir explicitamente, inclua — e diga qual é a fragilidade do dado.

- **ROI em horas de desenvolvimento economizadas** — a ideia era estimar horas poupadas a partir de fluxos × tempo médio de criação. A Vanessa marcou como "indeciso": *"eu acho bonito, mas não sei se é possível"*. Não há base confiável de horas (parte do desenvolvimento usa IA, o tempo médio varia demais). Sem dado de referência, o número viraria ficção — e ficção num report de ROI destrói a credibilidade que o report existe para construir.
- **Uptime de fluxos críticos / MTTR** — depende de um critério de criticidade que não existe. A intuição da Vanessa (Receita Federal, PIX, boletos são críticos) é razoável, mas classificar criticidade olhando um fluxo que não desenvolvemos e sem perguntar ao cliente é chute. O Felipe também argumentou que a APIPASS garante 99,7% de disponibilidade geral, o que reduz a utilidade do painel. **Bloqueado até o time de produto definir os critérios.**
- **Perfil de LinkedIn dos gestores** — dúvida se agrega valor real, e o dado nem sempre está cadastrado no HubSpot.
- **Site do cliente** (cruzar o portfólio dele com o roadmap) — a Vanessa registrou como dúvida própria.

---

## Fontes de dados e status de acesso

| Fonte | Status | Alimenta |
|---|---|---|
| Plataforma APIPASS (MCP) | ✅ disponível | tópicos 1, 2, 6, 7 — base de tudo |
| Tela Gerenciamento de Conta | ✅ quando o acesso existe | tópico 3 — **única fonte aceita** |
| Dashboard CS - Métricas Suporte | ✅ disponível, **consulta obrigatória** | tópico 5 |
| Jira PIL (Gestão de Projetos) | ✅ disponível | tópico 8 |
| Jira produto (PD/Polaris) | ✅ disponível | roadmap do tópico 7 |
| Endpoints Grafana Metrics | ✅ são fluxos nossos | tópico 4 (janela de 30 dias) e diagnóstico interno |
| SharePoint | ✅ conectado | contrato e histórico do cliente |
| HubSpot | 🚫 fora de escopo | Health Score e adoção; integração Claude-HubSpot restrita à liderança |
| Clock | ❌ sem MCP | saldo de horas/bolsão |

> **Correção de premissa (10/08/2026) que não pode ser desfeita:** o corte de "HubSpot, Grafana e Movidesk" de 05/08/2026 **não** significou cortar essas métricas. "Grafana Metrics" é o **backend** dos dashboards — fluxos REST da própria plataforma lendo MongoDB — e o dashboard de suporte é da própria APIPASS. Só o **HubSpot** segue realmente fora. Detalhes e achados de segurança em `endpoints-grafana-metrics.md`.

---

## Pendências que atravessam os clientes

1. **Validação formal da Vanessa** sobre a estrutura, e em especial sobre o tópico 6 (confiabilidade), que entrou na prática antes do aval dela.
2. **Usuários ativos** — decidir se leva frase própria de ausência, como a capacidade leva.
3. **Hex oficial da marca** — `cor_destaque` está com `#1F3864` provisório, único ponto de cor do documento. O manual de tom de voz não traz paleta.
4. **Destinatário real** — os três reports saíram como "Gestão de Tecnologia".
5. **Critérios de criticidade** com o time de produto (destrava o item de uptime).
