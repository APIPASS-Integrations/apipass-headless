---
name: analise-risco-churn
description: Monta a análise de risco de churn da base APIPASS — classifica clientes por faixa de acesso, cruza com adoção de produto, criação de projetos novos e inadimplência, e devolve uma lista priorizada com os critérios que pesaram e a ação sugerida. Use quando CS pedir "análise de churn", "quem está em risco", "clientes inativos", "risco de churn do cliente X", "health score" ou priorização de contas para contato.
---

# Análise de Risco de Churn — CS APIPASS

## Contexto (orientar o raciocínio, não repetir para o usuário)

Mapeado na reunião "Agenda interna - Skills Claude - CS" (30/07/2026, Fathom call 767320050) com Vanessa Costaldello. **Prioridade Média.**

Hoje a Vanessa faz conta por conta no Grafana: abre a conta, filtra 30 dias, anota o número de acessos, repete. Palavras dela: *"eu fiz uma vez manual pra ter direcionamento, mas é foda ter que fazer manual o tempo inteiro."* Depois cruza na mão com Health Score e adoção de produto no HubSpot. A análise ela sabe fazer — **o gargalo é o input do dado.**

Então o valor desta skill está em: coletar/consolidar, cruzar e priorizar. **Não** em dar o veredito.

## Regra central: acesso isolado não é indicador

Este é o erro que a skill existe para evitar. Dois contra-exemplos reais que a Vanessa deu, e que devem ser respeitados:

- **Uma conta que churnou com zero acesso** — o zero estava lá, sim. Mas o motivo real foi entrada por projeto pontual, somada a uma parceria de implantação que não se sustentou. O acesso baixo *acompanhou* o churn; não o causou nem o previu sozinho.
- **Cliente com 21+ acessos/mês, quase diário** — churnou também. Não reduziu execução, não reduziu fluxo, manteve-se acima de 50% de uso. Estava **internalizando as integrações**, e a APIPASS só soube porque o próprio cliente contou, um ano antes.

Conclusão operacional: **uso saudável não é ausência de risco, e zero acesso não é presença de risco.** Sempre reportar critérios *combinados*, com o peso de cada um visível. Nunca escrever "cliente X vai churnar" — escrever "cliente X acumula N critérios de risco; recomenda-se validação com CS/arquiteto".

Hierarquia de peso, conforme a Vanessa:
- **Peso alto (dado bruto, automatizável):** zero/baixo acesso · adoção abaixo de 10% · nada novo criado em 6-12 meses · inadimplência financeira · renovação próxima.
- **Peso baixo:** suporte. Literalmente *"o suporte é o menor deles"*. Volume de chamados por si só não indica churn.
  - *Nota de fonte (27/08/2026):* o dado de suporte **existe** e é consultável no **Dashboard CS - Métricas Suporte** da própria APIPASS — a premissa de "Movidesk sem MCP" foi corrigida. Peso segue baixo por decisão da Vanessa, não por falta de fonte. ⚠️ E o histórico **expira em 3 meses**, então esse sinal não serve para série longa. Mecânica em `../report-estrategico-trimestral/references/dashboard-suporte-movidesk.md`.
- **Não automatizável:** qualidade do relacionamento, cliente que não responde mais, termômetro da CS. É *feeling* da Vanessa somado à leitura dos arquitetos que trabalham a conta. Deixar como campo de input, nunca inferir.

## Faixas de classificação por acesso (30 dias)

Padrão já em uso pela CS (`Downloads\CS\[FUP] - Métricas Customer Success (Login últimos 30 dias).csv`):

| Faixa | Critério | Risco | Ação |
|---|---|---|---|
| Inativo | 0 acessos nos últimos 30 dias | Muito Alto | Contato imediato |
| Baixo uso | 1 a 5 acessos | Alto | 2º contato imediato |
| Uso moderado | 6 a 20 acessos | Médio | Avaliar adoção e oportunidades |
| Uso saudável | 21+ acessos | Baixo | Manter relacionamento |

Esta faixa é **entrada**, não resultado. O risco final sai do cruzamento do passo 3.

## Passo 1 — Coletar o que é automatizável (MCP APIPASS)

- `list_projects` — data de criação dos projetos por conta → responde **"criou algo novo nos últimos 6/12 meses?"** (critério de peso alto, hoje 100% manual).
- `list_flows` — fluxos novos no período, mesma lógica; também identifica fluxos de teste/abandonados.
- `get_usage_summary` / `get_execution_summary` — execuções no período. Cruzando com o plano contratado dá a **adoção de produto** (execuções ÷ plano contratado), que é exatamente a métrica de 0-10% que a Vanessa usa no HubSpot. Carregue `/apipass-integrations:apipass-usage` para a mecânica.
- Tendência de execuções mês a mês — queda sustentada é sinal, mesmo em conta com acesso saudável (foi o caso do cliente que internalizou; a queda de execução apareceria antes do churn ser anunciado).

### 🔴 O gargalo do input pode estar resolvido — verificar antes de pedir export

**Correção de premissa (10/08/2026), descoberta na skill do report estratégico.** Esta skill assume que os acessos por conta só vêm de export manual do Grafana. Mas o projeto **"Grafana Metrics" da conta `apipass` é o backend dos dashboards** — 15 fluxos REST da própria plataforma lendo MongoDB. O "Grafana" é só a camada de renderização.

Entre eles existe **`users-metrics/users-login-by-account`**, que devolve logins de usuário por conta. Detalhes em `../report-estrategico-trimestral/references/endpoints-grafana-metrics.md`.

**Por que isso importa mais aqui que no report:** o endpoint tem **janela fixa de 30 dias**, e foi justamente isso que manteve "Usuários ativos" sem dado no report trimestral. Mas as faixas de classificação desta skill são **exatamente de 30 dias** — a limitação que atrapalha lá é o formato certo aqui.

⚠️ **Antes de tratar como resolvido, confirme dois pontos:** a **retenção de eventos do Keycloak** (não verificada — pode não cobrir 30 dias completos) e se o endpoint devolve **todas** as contas ou exige lista. Enquanto não confirmado, mantenha o pedido de export como caminho paralelo.

⚠️ **Uso interno, e a fronteira importa.** Para **report que vai ao cliente**, a regra é outra: a fonte autorizada é a tela, e dado obtido por endpoint que contorna permissão de tela **não entra no documento** (ver `feedback` da Elisama em 26/08/2026). Análise de churn é material **interno** de CS, então o endpoint serve — mas não migre número daqui para um report de cliente sem passar pela tela.

## Passo 2 — Pedir o que falta (de uma vez, sem travar)

1. **Acessos por conta nos últimos 30 dias** — **primeiro tente o endpoint** acima; export do Grafana é o plano B. Se vier CSV/planilha, ótimo: analisar arquivo é melhor do que print.
2. **Plano contratado por cliente** (execuções/mês) — para calcular adoção. Fonte: SharePoint (pasta do cliente) ou HubSpot.
3. **Health Score e adoção do HubSpot**, se disponível — integração Claude-HubSpot ainda restrita à liderança; o painel é acessível manualmente.
4. **Situação financeira / inadimplência** — não há fonte conectada.
5. **Data de renovação** dos contratos em janela próxima.
6. **Análise histórica de churn 2023-2026** — a Vanessa tem, e concordou que é caminho extrair dela as causas já identificadas. Se ainda não foi compartilhada, pedir; enquanto não vier, usar os critérios desta skill.

Se algo não vier, **não travar**: rode com o que existe, marque quais critérios não puderam ser avaliados, e diga qual conclusão fica frágil por causa disso.

## Passo 3 — Cruzar e priorizar

Para cada conta, marque quais critérios batem:

- [ ] Acesso: faixa Inativo ou Baixo uso (30d)
- [ ] Adoção de produto abaixo de 10% (execuções ÷ plano contratado)
- [ ] Nenhum projeto ou fluxo novo em 6-12 meses
- [ ] Tendência de execuções em queda sustentada
- [ ] Inadimplência financeira
- [ ] Renovação nos próximos meses
- [ ] Relacionamento desafiador / sem resposta *(input da CS)*
- [ ] Suporte com padrão anômalo *(peso baixo — só como contexto)*

Priorize por **quantidade e peso** de critérios simultâneos, não por um só. O cenário de risco máximo descrito pela Vanessa é a soma: não acessa + não traz nada novo há 6-12 meses + renovação próxima + engajamento abaixo de 20% + inadimplência.

Reporte também, em seção separada, as **contas de uso saudável com sinal contraditório** (ex.: 21+ acessos mas execuções caindo, ou nenhum projeto novo há um ano). É a categoria que hoje passa batido — e foi exatamente ela que gerou um churn surpresa.

## Passo 4 — Entregável

1. **Lista priorizada** — conta, faixa de acesso, critérios que bateram, quantidade de critérios, ação sugerida.
2. **Seção de sinais contraditórios** — uso saudável com indício de risco.
3. **Critérios não avaliados** — quais fontes faltaram e o que isso enfraquece na conclusão.
4. Se o usuário pedir visual, um HTML/Artifact com a tabela ordenada por risco funciona bem para revisão rápida.

Ações a sugerir (vocabulário já usado pela CS): contato imediato · 2º contato · visita · reunião urgente · bonificação · avaliar adoção e oportunidades · manter relacionamento. A escolha final da ação é da CS — a skill sugere, não decide.

## Norte de médio prazo (registrar quando o assunto voltar)

A solução que a Vanessa quer de verdade é **levar os dados de plataforma para o HubSpot** — campos de quantidade de acessos no período e "criou algo novo nos últimos 6 meses (sim/não)" — para que o Health Score do HubSpot calcule o risco automaticamente, já cruzado com adoção de produto. Isso é uma integração APIPASS→HubSpot, não uma skill. Alternativa levantada por ela caso o HubSpot não libere: consolidar essa visão no próprio Claude/Cloud.

Enquanto isso não existir, esta skill é o paliativo — e vale mencionar o norte quando a conversa for sobre automatizar de vez.
