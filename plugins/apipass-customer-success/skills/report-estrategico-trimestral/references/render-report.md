# Render do report — schema do JSON e mecânica de Word COM

O script `scripts/New-ReportDocx.ps1` implementa tudo isto. Este documento existe para (a) o schema do JSON de entrada, (b) a definição das três variantes de layout e (c) registrar as armadilhas de COM específicas de Word.

As **12 armadilhas gerais de COM** estão em `../../extrato-consumo/references/render-lamina.md` e não são repetidas aqui.

### O gráfico NÃO usa Excel COM — e por quê

Desvio deliberado em relação ao `extrato-consumo`. Lá o "gráfico" é uma tabela, e renderizar um range do Excel como PNG é o caminho certo. Aqui é um gráfico de 3 barras, e fazê-lo por **GDI+ (`System.Drawing`)** dentro do próprio PowerShell:

- elimina uma dependência COM não verificada no WPS (`Chart.SetSourceData`);
- evita de cara a armadilha nº 1 do `render-lamina.md` — `Range.Value2` só aceita String no WPS, e um chart alimentado por texto plota barras de altura zero;
- dá controle exato de posição de rótulo, que é onde o gráfico deu problema de verdade (ver abaixo).

## Schema do JSON de entrada

Escreva em **UTF-8**. **Todo** texto visível ao cliente vem daqui — inclusive títulos de seção e rótulos fixos, no bloco `rotulos`. O `.ps1` é ASCII puro de propósito, para não depender do encoding com que o `powershell.exe` interpreta o script; a consequência é que qualquer string escrita nele sai **sem acento** no documento.

> Erro cometido e corrigido em 05/08/2026: a primeira versão tinha os títulos hardcoded no script, e o PDF saiu com "Visao geral do ambiente", "Integracoes ativas" e "Nao constam nesta edicao". O script agora usa o bloco `rotulos` e **emite pendência sempre que cai no fallback ASCII**, nomeando as chaves ausentes.

Acento saindo como `Ã§` é sintoma de JSON gravado fora de UTF-8, não de fonte.

```json
{
  "meta": {
    "titulo": "Report Estratégico Trimestral",
    "cliente": "Conta A",
    "trimestre": "2026Q2",
    "periodoLabel": "abril a junho de 2026",
    "geradoEm": "05/08/2026",
    "destinatarios": "Coordenação de TI",
    "parcial": false,
    "corDestaque": "#1F3864"
  },

  "rotulos": {
    "ambiente": "Visão geral do ambiente",
    "crescimento": "Capacidade de crescimento",
    "confiabilidade": "Confiabilidade das integrações",
    "oportunidades": "Oportunidades de uso",
    "atividades": "Atividades em andamento",
    "projetosAtivos": "Projetos ativos",
    "integracoesAtivas": "Integrações ativas",
    "integracoesProd": "Em produção",
    "integracoesSufixo": "integrações",
    "areasAtendidas": "Áreas de negócio atendidas",
    "execucoes": "Execuções",
    "execucoesTrimestre": "Execuções no trimestre",
    "sistemasIntegrados": "Sistemas integrados",
    "adicionadoNoTrimestre": "Adicionado no trimestre:",
    "taxaSucesso": "Taxa de sucesso",
    "naoConstam": "Não constam nesta edição:"
  },

  "resumo": "Duas a três frases de abertura, em linguagem de negócio.",

  "ambiente": {
    "projetosAtivos": 12,
    "integracoesAtivas": 87,
    "integracoesProd": 74,
    "sistemas": ["Protheus", "WMS"],
    "areas": [ { "area": "Logística", "integracoes": 23, "descricao": "expedição e rastreio de cargas" } ],
    "aClassificar": ["Integrações/Rotina 04"]
  },

  "crescimento": {
    "temBaseline": true,
    "baseline": { "trimestre": "2026Q1", "projetos": 10, "integracoes": 78, "execucoes": 1201543, "contratado": 2000000 },
    "atual":    { "projetos": 12, "integracoes": 87, "execucoes": 1456201, "contratado": 2000000 },
    "legenda": "Explica o que as linhas medem. Obrigatória quando a tabela mistura naturezas.",
    "novos": [ { "nome": "Integrações - Fiscal", "tipo": "projeto", "paraQueServe": "emissão de NF-e" } ],
    "rotuloMediaBaseline": "média mensal 2026Q1",
    "contratadoMensal": 200000,
    "rotuloContratado": "ambiente contratado",
    "serieMensal": [ { "mes": "abr/2026", "execucoes": 452031 } ],
    "leitura": "Frase que traduz o número em ganho de negócio."
  },

  "capacidade": {
    "engine": "Flow Engine Produção",
    "fluxosImplementados": 12,
    "fluxosContratados": 20,
    "percentualUso": "60%",
    "leitura": "Há espaço contratado para mais 8 integrações em operação."
  },

  "confiabilidade": {
    "execucoes": 1456201, "execucoesComErro": 8734,
    "taxaSucesso": "99,4%",
    "leitura": "..."
  },

  "oportunidades": [
    { "titulo": "Arquivamento de fluxos de teste",
      "evidencia": "9 fluxos nomeados \"teste\" no ambiente",
      "oportunidade": "a funcionalidade de arquivamento já está disponível e despolui a tela de projetos" }
  ],

  "atividades": [ { "time": "CSM", "responsavel": "Vanessa", "descricao": "..." } ],

  "naoConstam": [
    { "secao": "Usuários Ativos", "motivo": "métrica de acesso não disponível nesta edição" }
  ],
  "pendencias": ["Plano contratado não informado — seção de oportunidades saiu sem o comparativo de capacidade"]
}
```

Regras de presença — o renderizador nunca inventa e nunca deixa buraco silencioso:

| Chave | Ausente significa |
|---|---|
| `crescimento.temBaseline: false` | primeiro trimestre medido. O bloco vira "linha de base estabelecida neste trimestre" e **não** mostra comparativo. `baseline` pode vir `null`. |
| `capacidade` | bloco não renderizado. Fonte: `grafana/usage-metrics/flow-engine-summaries` com `family=f` (ver `endpoints-grafana-metrics.md`). **Enquadramento obrigatório: capacidade disponível para crescer, nunca sobra ociosa** — "contratou X, usa Y" faz o cliente concluir que deve *reduzir* o plano. O bloco mostra o que cabe, não o que sobra. |
| `confiabilidade` | bloco não renderizado. **A decisão de incluir é da coleta, não do render** — o renderizador só honra a presença da chave. Bloco ainda pendente de validação com a Vanessa. |
| `atividades` vazio | bloco omitido e o item entra automaticamente em `pendencias` (é input manual por definição). |
| `ambiente.aClassificar` não vazio | renderiza como nota interna de rodapé — **é sinal de que falta preencher o `mapa_area_negocio` da config**, e não deve ir para o cliente assim. |
| `naoConstam` | as ausências são impressas **em texto** no fim. Omitir em silêncio faria o gestor concluir que a APIPASS não tem o dado. |
| `rotulos.<chave>` ausente | sai o fallback ASCII, **sem acento**, e entra pendência nomeando a chave. Nunca enviar ao cliente assim. |
| `baseline.contratado` / `atual.contratado` ambos `null` | a linha "Execuções contratadas" **não é renderizada**. Tabela sem referência de capacidade é preferível a referência inventada — o gestor decide plano com base nela. |
| `crescimento.legenda` ausente | tabela sai sem legenda. **É o default correto** — ver abaixo. |

### Legenda da tabela: só se agregar leitura

Reprovada pela Elisama em 12/08/2026, e a lição vale para qualquer texto de apoio no report.

A primeira versão explicava a diferença entre "com execução" (na tabela) e "ativas" (na visão geral). Veredito dela: *"não agregou valor"*. Estava certo — o texto **explicava a nossa contabilidade, não o negócio do cliente**. Vira disclaimer conciliando dois números nossos, e para um gestor isso não informa: faz ele desconfiar da tabela em vez de ler o crescimento. Ficou redundante também, porque os rótulos das linhas já dizem o que medem.

**Regra:** legenda entra apenas quando carrega leitura que o gestor não tira do rótulo. Se o texto existe para reconciliar nomenclatura interna, o problema é o rótulo — conserte o rótulo e apague a legenda.

Cuidado ao tentar "melhorar" reenquadrando a diferença como capacidade disponível (ex.: *"das 55 implantadas, 31 processaram — as outras estão prontas para operar"*): **é falso**. Boa parte da diferença é **subfluxo, que nunca registra execução por definição**, e no caso da Conta A 10 são de POC/treinamento. A frase soaria bem e estaria errada.

### Rótulos próprios da tabela de crescimento (adicionados em 12/08/2026)

`crescProjetos`, `crescIntegracoes`, `crescExecucoes`, `crescContratado`.

**Não reaproveitar `projetosAtivos`/`integracoesAtivas` aqui.** No bloco de ambiente esses rótulos contam o que está **implantado**; na tabela de crescimento as linhas medem o que **executou no trimestre**. Com o mesmo rótulo nos dois lugares, o gestor vê `10` na visão geral e `9` na tabela para a "mesma" coisa e conclui que um dos dois está errado. Foi o que aconteceu na v1 do report da Conta A.

Motivo de a métrica ser "com execução" e não "ativos": **contagem de ativos não se reconstrói para trás** (é fotografia, depende de snapshot). "Com execução" é recalculável a qualquer momento e, para justificar volume, é a métrica mais honesta — o que explica N execuções é quanta integração rodou, não quanta estava cadastrada.
| `crescimento.rotuloMediaBaseline` ausente | a legenda do gráfico sai sem acentuação (é texto desenhado, não editável no .docx). Pendência emitida. |
| `crescimento.contratadoMensal` presente | o gráfico ganha uma **segunda linha de referência** (ponto-traço, na cor de destaque, para não confundir com a linha cinza de média) e uma segunda entrada de legenda. |
| `crescimento.contratadoMensal` ausente | **nenhuma segunda legenda e nada no lugar dela.** O gráfico sai no padrão. Pendência emitida. |
| `crescimento.notaContratado` presente | **campo eliminado do contrato.** O script ignora e emite pendência pedindo que seja removido do JSON. |

### 🚫 O padrão do gráfico nunca muda

**Regra da Elisama, 26/08/2026:** *"Vc deve manter o padrão do gráfico independente de qualquer coisa (…) o padrão do gráfico nunca muda"*.

O gráfico é o mesmo para todo cliente: barras com o absoluto, rótulo do mês, linha de média do trimestre anterior. A **linha de capacidade contratada** é o **único elemento opcional** e entra somente quando houve **acesso à tela de Gerenciamento de Conta** — nunca por dado obtido em outra fonte.

**Nada é injetado no PNG para explicar ausência de dado.** O parâmetro `notaContratado` de `New-BarChartPng` **foi removido**, junto com o ramo `else` que desenhava a nota. Não reintroduzir: foi ele que fez o gráfico da Conta A sair diferente dos outros dois clientes.

**Ausência se declara em `naoConstam`** — texto do documento, na linha "Não constam nesta edição". É o que se lê, se busca e se copia.

> Dois erros meus no mesmo ponto, em 12/08 e 26/08/2026. No primeiro pus a nota **só na legenda do gráfico** e considerei atendido: texto desenhado dentro do PNG não é nota do documento — é cinza pequeno no rodapé de uma imagem, não dá para buscar nem selecionar, e a Elisama não encontrou no arquivo. No segundo, "corrigi" a ausência **buscando o dado por outro endpoint** e pondo no report; pior ainda, porque preencheu o documento com um número que quem assina não tem acesso para conferir. A conclusão dos dois é a mesma: **o gráfico não é lugar de explicação, e ausência de acesso não se contorna.**

Ausência sem explicação faz o gestor concluir que o dado não existe; ausência nomeada **em texto** mostra que existe e está a um acesso de distância.

Duas armadilhas medidas ao implementar:

1. **A nota precisa de quebra de linha por palavra.** É uma frase, não um rótulo curto — sem quebra ela é desenhada até sair do bitmap e termina cortada no meio da palavra (`...desta con`). A quebra mede na fonte real, com `MeasureString`.
2. **`padB` tem que crescer com a quantidade REAL de linhas**, incluindo as da nota quebrada. Valor fixo estourava o bitmap quando a nota ocupava duas linhas.

**A quota é mensal, e a tela filtra por mês/ano.** Então `contratadoMensal` é comparável direto com as barras — nada de dividir trimestre por 3. Mas **colete os 3 meses do trimestre**: uma linha de referência única assume quota constante, e se o plano mudou no meio do período a linha mente. Se os três valores divergirem, declare a variação em vez de desenhar a linha.

**Escolha de público, que é decisão da CS por edição:** a nota técnica (`"a APIPASS não tem permissão de acesso à aba…"`) serve ao rascunho interno, onde explica ao revisor por que a linha falta. Para a versão que vai ao gestor do cliente, considere uma formulação neutra — `"Ambiente contratado: a confirmar."` — porque a versão técnica expõe um problema de acesso interno num documento cuja função é transmitir controle. O texto vem do JSON justamente para permitir as duas versões sem tocar no script.

## As três variantes de layout

O formato acordado é **1 a 2 páginas**. Com Usuários Ativos e Suporte fora desta edição, sobram 4 blocos: Ambiente, Crescimento, Oportunidades, Atividades.

Word não faz layout visual bem, então as variantes não são três templates — são três arranjos dos mesmos blocos, selecionados por `-LayoutVariant`:

- **A — empilhado.** Uma seção por bloco, na ordem da `estrutura-report.md`, gráfico no topo do bloco de crescimento. O mais conservador e o que menos risco tem de estourar a segunda página.
- **B — faixa de KPI.** Quatro cards no topo (projetos ativos · integrações ativas · áreas de negócio atendidas · execuções no trimestre) e o resto em tabelas sem borda. A faixa originalmente traria "usuários ativos"; foi substituída por áreas de negócio, que sai do MCP.
- **C — duas colunas.** Ambiente e crescimento à esquerda, oportunidades à direita, atividades em rodapé de largura total.

Implementação das colunas da variante C: **tabela de 2 colunas sem borda**, não `Section.TextColumns`. Colunas de seção via COM exigem quebra de seção e reflow, e a contagem de páginas fica imprevisível — o que quebra o guard abaixo.

Cards de KPI e blocos comparativos são **tabelas sem borda com sombreamento de célula**, que é o truque padrão de Word para isso.

## Guard de páginas — por que existe

`Document.ComputeStatistics(wdStatisticPages = 2)` depois de montado. Se passar de `-MaxPages` (default 2), o script **sai com código de erro** e diz qual bloco tem mais linhas, em vez de gerar o PDF.

O motivo é o mesmo dos guards de exit 2/exit 3 do `Get-DashboardPrint.ps1`: sem o guard, um cliente com 40 projetos gera um report de 5 páginas que ninguém confere antes de mandar para o gestor — e um "executive summary" de 5 páginas não é lido. Estourar é sinal de que o conteúdo precisa ser resumido, não de que o formato deve ceder.

### Orçamento de linhas — medido, não estimado

Quando estourar, **meça antes de cortar.** Medido em 26/08/2026 nos três entregáveis do 2026Q2, no layout B:

| Cliente | Páginas | Linhas | Palavras |
|---|---|---|---|
| Conta C | 2 | 98 | 886 |
| Conta B | 2 | 101 | 916 |
| Conta A (antes do corte) | **3** | 104 | 929 |

**O teto prático é ~101 linhas.** Acima disso vira a página. E o excesso costuma ser mínimo — no caso da Conta A o que vazava para a página 3 era **só a linha de assinatura**.

```powershell
# um documento por instancia de COM: reaproveitar a instancia deu "O servidor RPC nao esta disponivel"
$doc.ComputeStatistics(2)   # paginas
$doc.ComputeStatistics(1)   # linhas  <- o numero que interessa
$doc.ComputeStatistics(0)   # palavras
# onde vira a pagina, paragrafo a paragrafo:
$par.Range.Information(3)   # wdActiveEndPageNumber
```

**Onde cortar, em ordem:** primeiro a **repetição** entre blocos, que sai sem perder informação — o `resumo` costuma repetir os números que a faixa de KPIs mostra logo abaixo, e a leitura de `confiabilidade` costuma repetir a decomposição sucesso/erro que a de `crescimento` é obrigada a trazer. Só depois encurte descrição de frente de negócio. **Nunca** suba o `-MaxPages` para caber, e **nunca** remova um dos 8 tópicos: eles são iguais para todo cliente por decisão da Elisama, e o script renderiza o tópico ausente como `[Em construção]` de propósito.

## Cores

Word COM recebe cor em **BGR**, não RGB. `#1F3864` → `0x64381F`. O helper do script converte; não passe hex direto.

`meta.corDestaque` é o único ponto de cor. O default `#1F3864` é **provisório** — o hex oficial da marca APIPASS não está registrado em nenhum lugar deste ambiente. Confirmar com marketing antes da primeira entrega ao cliente.

## Export para PDF — medido em 05/08/2026

`Document.ExportAsFixedFormat(OutputFileName, ExportFormat = 17)` **funciona** no Word COM servido pelo WPS desta máquina — confirmado nas três variantes. O script imprime qual caminho usou (`[via ExportAsFixedFormat]`).

O fallback `SaveAs([ref]$path, [ref]17)` (`wdFormatPDF`) segue no código porque o método pode não existir em outra instalação, mas **não foi exercitado** — se algum dia o log mostrar `[via SaveAs(wdFormatPDF)]`, é a primeira vez que esse caminho roda.

## Armadilhas de Word COM no WPS — todas medidas em 05/08/2026

Cada item abaixo custou um ciclo de execução:

1. **`Table.Rows.SpaceBetweenColumns` lança `E_FAIL`.** Derrubava o script inteiro no primeiro `Tables.Add`. Padding de célula é cosmético: o script tenta, cai para `LeftPadding`/`RightPadding` e segue. **Nunca deixar propriedade cosmética sem `try`.**

2. **Não chame uma função de `R`.** `R` é alias nativo de `Invoke-History`, e **alias tem precedência sobre função** no PowerShell. O sintoma não é "função não encontrada", é `não é possível localizar um parâmetro posicional que aceite o argumento '<seu texto>'` — que parece erro de assinatura da sua própria função. O helper de rótulos chama-se `Rot`.

3. **`Close` + `Quit` não bastam para liberar o COM.** Cinco execuções deixaram **cinco processos `wps` headless vivos**, e a sexta falhou com `Falha Ao Salvar` porque o órfão ainda segurava o `.docx`. O que de fato solta a referência é `[Runtime.InteropServices.Marshal]::ReleaseComObject()` antes do `GC::Collect()`. Mesmo com isso, ainda sobra órfão ocasional — **se um run falhar ao salvar, procure processo órfão antes de procurar bug no script.**

4. **Colunas da variante C são tabela, não `Section.TextColumns`.** Colunas de seção exigem quebra de seção e o reflow deixa a contagem de páginas imprevisível, o que quebraria o guard.

5. **Legenda de gráfico não vai junto da linha de referência.** Desenhada na altura da linha tracejada, ela saía **por cima das barras** e ficava ilegível (a primeira versão imprimiu `media...400.514` com o meio coberto pela barra de junho). A legenda vive no rodapé, com `padB` maior quando há linha de base.

6. **Junte evidência e oportunidade com travessão, não ponto.** `". "` produzia "no ambiente. a funcionalidade..." — minúscula depois de ponto, num documento que vai para o gestor decisor.

## Cleanup

`Close` → `Quit` → `ReleaseComObject` → `GC::Collect()` (duas vezes), tudo em `finally`. Antes de matar processo órfão, conferir `MainWindowTitle`: **vazio é automação headless, preenchido é documento aberto por uma pessoa** — matar o segundo perde o trabalho de alguém.

```powershell
Get-Process -Name wps -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowTitle -eq '' } | Stop-Process -Force
```

⚠️ **O PID que tem `MainWindowTitle` pode estar segurando MAIS de um arquivo.** O WPS é instância única com abas: em 27/08/2026 uma janela intitulada "…Conta C.pdf" travava também os PDFs da Conta A e da Conta B. O sintoma é o build gerar o `.docx` e falhar só no `ExportAsFixedFormat`. **Peça para a pessoa fechar os arquivos**; não mate o processo.

---

## Rasterizar SVG para PNG — Chrome headless

Descoberto em 27/08/2026, ao entregar a lâmina de resumo do report. **Este ambiente não tem rasterizador de SVG**: sem `magick`, sem `inkscape`, sem `rsvg-convert`. E cuidado — `convert.exe` existe em `C:\WINDOWS\system32` mas é o **conversor de FAT para NTFS**, não o ImageMagick.

O caminho que funciona é o Chrome, que está instalado em `%ProgramFiles%\Google\Chrome\Application\chrome.exe`:

```powershell
# 1. embrulhe o SVG num HTML sem margem, com o tamanho exato
$html = "<!doctype html><html><head><meta charset=""utf-8""><style>" +
        "html,body{margin:0;padding:0;overflow:hidden}svg{display:block;width:1600px;height:900px}" +
        "</style></head><body>" + $svg + "</body></html>"
[IO.File]::WriteAllText($wrap, $html, (New-Object Text.UTF8Encoding($false)))

# 2. screenshot em 3x -> 4800 x 2700
$argsList = @("--headless=new","--disable-gpu","--hide-scrollbars","--no-first-run",
              "--force-device-scale-factor=3","--window-size=1600,900",
              "--user-data-dir=$udd","--screenshot=$out", "file:///" + $wrap.Replace("\","/"))
Start-Process -FilePath $chrome -ArgumentList $argsList -Wait -NoNewWindow
```

Três armadilhas, todas pagas em tempo:

1. **`--user-data-dir` próprio é OBRIGATÓRIO.** Se o Chrome já estiver aberto (e está, quase sempre), o processo novo se anexa à instância existente e **não gera nada**, sem erro.
2. **O caminho de saída não pode ter espaço.** O `-ArgumentList` do `Start-Process` quebra em espaços, o `--screenshot=` chega partido e o Chrome falha com *"Multiple targets are not supported in headless mode"*. Renderize num caminho sem espaço e **copie depois** para o nome final.
3. **Não use `-replace '\\','/'` na mesma linha de um `Remove-Item`** — o hook de permissão interpreta o padrão como caminho a remover e bloqueia. Use `.Replace("\","/")` e separe as chamadas.

Vantagem sobre a captura Win32 (`CopyFromScreen`): o Chrome renderiza **fora da tela**, então escapa do escurecimento por HDR que estraga print nesta máquina. Para fundo transparente, `--default-background-color=00000000`.

## 🔴 Verificação: rasterize e OLHE

Regra que saiu de três rodadas de entrega da mesma lâmina em 27/08/2026. Eu validei o SVG como XML bem formado, rodei uma checagem de largura por coluna e afirmei "sem estouro" — **e havia um defeito visível**: no cabeçalho da tabela, `EXECUÇÕES` e `TAXA DE SUCESSO` estavam colados, lendo como uma frase só. Minha checagem media a largura do texto e **ignorava o `letter-spacing`**, que naqueles rótulos em caixa alta somava quase 20 px.

- **A validação estava certa no que media e cega no que faltava.** Rasterizar e ler a imagem era o passo que faltava, e agora é barato.
- Se for estimar largura de texto: `chars × (fontSize × 0.52 + letterSpacing)`, e **cheque colisão entre vizinhos na mesma linha**, não só estouro da borda.
- Prefira **fluxo natural** (`<tspan>` sem `x`) a posicionar continuação de linha em `x` fixo — assim sobreposição fica impossível em vez de precisar ser verificada.

## 🔴 Zero de comando que falhou não é evidência

Errei isso duas vezes em 26–27/08/2026, e as duas vezes eu quase reportei "conferido, zero ocorrências":

- `Expand-Archive` **não aceita `.docx`** — a extração falhou, o `grep` não achou nada, e o "0" não significava nada. Use `unzip -p arquivo.docx word/document.xml`.
- Chamei um script sem um parâmetro **obrigatório** (`-OutTxt`): ele saiu antes de fazer qualquer coisa, e a busca no resultado vazio devolveu 0.
- `unzip` **não existe no PowerShell** desta máquina, só no Bash. Rodar lá deixa a variável vazia e a checagem "passa".

**Antes de confiar num zero, confirme que o comando produziu bytes.** Imprima o tamanho do que foi extraído junto do resultado da busca.
