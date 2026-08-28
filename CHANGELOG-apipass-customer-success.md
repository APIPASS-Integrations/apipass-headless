# Changelog — apipass-customer-success

## 0.1.0

Primeira versão. Três skills de Customer Success, construídas e validadas gerando material
real para quatro contas ao longo de agosto/2026. Todos os exemplos citam as contas sob
rótulo neutro (ver `plugins/apipass-customer-success/README.md`).

### Adicionado

- **Skill `report-estrategico-trimestral`** — gera o report de 1-2 páginas para o gestor do
  cliente. **Oito tópicos iguais para todo cliente**, na mesma ordem, com rótulos canônicos
  em `assets/rotulos-canonicos.json` e não no JSON do cliente: visão do ambiente, capacidade
  de crescimento, capacidade do ambiente, usuários ativos, suporte, confiabilidade,
  oportunidades de uso e atividades em andamento. Tópico sem dado **não desaparece** —
  renderiza declarado. Layout B (faixa de KPIs) é o padrão.
  - `scripts/New-ReportDocx.ps1`: monta o `.docx` via Word COM, desenha o gráfico em GDI+ e
    exporta PDF com `ExportAsFixedFormat`. **Guard de páginas**: se o documento passar de 2
    páginas, sai com erro (exit 4) em vez de entregar um "executive summary" de 5 páginas.
    Teto prático medido: **~101 linhas**.
  - **Arquivamento automático** do entregável vigente em `_versoes-antigas/` antes de
    sobrescrever, **por cópia**, uma por dia. É cópia e não move porque build que falha não
    pode destruir o entregável que já estava entregue — aprendido perdendo os `.docx` de três
    pastas de entrega de uma vez.
  - **Snapshot trimestral** em `snapshot-<AAAA>Q<N>.json`: execuções são recalculáveis, mas
    contagem de projetos e integrações ativas é fotografia e **não se reconstrói para trás**.
- **Skill `extrato-consumo`** — extrato mensal para cliente de faturamento por execução:
  coleta via MCP, cálculo de tier e faturamento, deck em PowerPoint COM, e print automatizado
  do dashboard.
- **Skill `analise-risco-churn`** — faixas de classificação por acesso em 30 dias, cruzadas
  com adoção de produto, criação recente de projeto e inadimplência. Devolve lista priorizada
  com os critérios que pesaram, **nunca** um veredito de churn.

### Regras de conteúdo que o report obedece

Cada uma nasceu de um erro cometido e corrigido em revisão. Estão nas `references/` com o
caso que as originou:

1. **Fonte autorizada.** A tela de Gerenciamento de Conta é a **única** fonte aceita para
   capacidade contratada. Dado tecnicamente correto obtido por endpoint que contorna a
   permissão de tela **não vai ao documento** — quem assina não o viu e não pode conferi-lo
   contra a tela que o cliente vê.
2. **Falta de autorização é declarada no documento**, em dois lugares, com texto canônico.
   Seção vazia sem explicação faz o leitor concluir que o relatório saiu com defeito.
3. **O padrão do gráfico nunca muda.** A linha de capacidade contratada é o único elemento
   opcional; **nada** é injetado no PNG para explicar ausência de dado. Ausência se declara
   em texto — legenda de gráfico é pixel, não dá para buscar nem selecionar.
4. **Queda de execuções é decomposta em sucesso e erro** antes de ir ao documento, e se
   compara sucesso contra sucesso. Sem isso o gestor lê redução de uso onde pode não haver
   nenhuma: num caso real o total caiu 9,1% enquanto as execuções concluídas com sucesso
   ficaram estáveis — a queda era de erro.
5. **Suporte leva quantidade e corte por serviço, nunca tempo de resolução** — sem dias
   corridos, dias úteis, horas ou mediana. Há guard no script.
6. **Nomeie quem causa o comportamento** — fluxo, projeto e stage. "Um subfluxo concentra 79%
   das requisições" é ruído: o gestor não sabe onde agir.
7. **Não escrever recomendação sem fonte.** Teste antes de publicar: consigo apontar a fonte
   de cada afirmação desta frase? Se a resposta passa por "faz sentido que", apague.
8. **Nada com peso comercial se decide sozinho.** Estouro de contrato, quota excedida, valor
   de fatura: apurar, apresentar as opções à CS, e escrever o que ela decidir.
9. **Terminologia:** sempre "publicar as integrações em produção", nunca "promover a
   produção".

### Armadilhas de plataforma documentadas

- **A deduplicação de linhas `period="flow"` NÃO é regra universal.** Em uma conta ela é
  necessária; em três outras ela **subnotifica** — a soma direta reproduz o
  `get_usage_summary` exato (30.800) e a deduplicada erra por 288. Quando o mesmo subfluxo é
  chamado por projetos diferentes, os pares repetidos são **fatias distintas**, não cópias.
  **Rode as duas somas e fique com a que fecha**; se nenhuma fechar, é a janela que está
  errada. O teste de consistência é o árbitro, não a regra escrita.
- **`startDate`/`endDate` são instantes UTC e `endDate` é inclusivo.** Para
  `America/Sao_Paulo`, o trimestre fecha em `T03:00:00.000Z` → `T02:59:59.999Z`. Data simples
  erra ~3% para baixo.
- **`info.flowsAmount` inclui fluxos arquivados** — a contagem autoritativa é o `totalItems`
  do `list_flows` com `archived="active"`.
- **`projectName` muda entre trimestres**: projetos são renomeados e remanejados. Série
  histórica ancora em `projectId`.
- **Subfluxo contribui zero execução** e acumula só requisição e tráfego. Isso é
  contabilização, **não** ociosidade — nunca apresentar como desperdício.
- **Retenção de log não alcança 5 meses**; a série agregada continua disponível.
- **O histórico do dashboard de suporte é expurgado após 3 meses**, e o campo de data tem
  `min` — o formulário **recusa a submissão** sem erro na página. Consequência operacional:
  tabular ticket a ticket na coleta e **gerar o report perto do fechamento do trimestre**.
- **Quota é mensal e não acumula.** Nunca somar as quotas do trimestre para criar um
  denominador: ele não existe em tela nem em contrato, e a média esconde o pico.
- **Tráfego vem em bytes e a plataforma divide por 1024³** ao rotular "GB" — verificado
  contra a tela. A diferença contra ÷10⁹ é de 7%.
- **Não usar `executionsUsagePercentage` para janela trimestral**: ele divide o total da
  janela pela quota mensal.

### Armadilhas de ambiente (Windows / Office COM)

- **`Close` + `Quit` não liberam o COM** — é preciso `ReleaseComObject` antes do
  `GC::Collect()`. Órfão de execução anterior quebra a execução **seguinte**, não a atual.
- **Antes de matar processo órfão, confira `MainWindowTitle`**: vazio é automação, preenchido
  é documento aberto por uma pessoa. E **um PID pode segurar vários arquivos** — o Office é
  instância única com abas, então o título nomeia só a aba ativa.
- **Não existe rasterizador de SVG neste tipo de ambiente**; o caminho é Chrome headless com
  `--force-device-scale-factor`, e ele exige `--user-data-dir` próprio (senão anexa à
  instância aberta e não gera nada) e caminho de saída **sem espaços**.
- O extrator de texto de PDF incluído **é cego para PDFs gerados pelo próprio Office COM** —
  para conferir um entregável, leia o `.docx`, não o PDF.
