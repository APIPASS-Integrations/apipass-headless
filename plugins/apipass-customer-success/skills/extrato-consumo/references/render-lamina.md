# Renderização das lâminas e montagem do PPT

O script `scripts/New-ExtratoPptx.ps1` já implementa tudo isto. Este documento existe para (a) o schema do JSON de entrada e (b) registrar **por que** cada constante é o que é — todas foram descobertas quebrando o script contra o deck real em 03/08/2026.

## Schema do JSON de entrada

Escreva em **UTF-8**. Todo texto acentuado vem daqui; o `.ps1` é ASCII puro de propósito, para não depender do encoding com que o `powershell.exe` interpreta o script.

```json
{
  "cliente": "Conta D",
  "itensPorLamina": 20,
  "capaTexto": "EXTRATO DE CONSUMO\rCONTA D RS – CONTRATO 18512024 Julho - 2026\r01/07 a 31/07",
  "rotulos":  { "projeto":"PROJETO","fluxo":"FLUXO","stage":"STAGE",
                "execucoes":"EXECUÇÕES","requests":"REQUESTS","trafego":"TRÁFEGO" },
  "titulos":  { "total":"Extrato de consumo total",
                "removidas":"Execuções a serem removidas" },
  "slideTotal":     { "totalPeriodo":"TOTAL DO PERÍODO 1.355.319" },
  "slideRemovidas": { "totalPeriodo":"TOTAL DO PERÍODO 177.753",
                      "totalFinal":"TOTAL FINAL DO PERÍODO 1.177.566 execuções" },
  "aceiteTexto": "Recebemos o aceite em 07/07/2026",
  "faturamento": {
    "rotulos": { "servico":"Serviço","qtde":"Qtde Execuções","unitario":"Valor unitário",
                 "total":"Valor Total","totalGeral":"Total Geral Final" },
    "fixos": [ { "servico":"Licença de uso da Plataforma","total":"R$ 3.580,88" } ],
    "tier":  { "label":"Tíer de Execuções: 3","qtde":"1.177.566",
               "unitario":"R$ 0,0X","total":"R$ 14.484,06" },
    "totalGeral":"R$ 22.734,11"
  },
  "avisos": {
    "colarPrintTotal":"COLAR AQUI o print do dashboard (mês completo, sem filtro de projeto)",
    "colarPrintProjeto":"COLAR AQUI o print do dashboard filtrado pelo projeto Serviços",
    "faltaMovidesk":"PENDENTE: export dos chamados do Movidesk",
    "faltaFaturamento":"PENDENTE: tabela de faturamento"
  },
  "chamadosColunas": ["Número","Tipo","Assunto","Aberto em","Categoria","Prioridade","Status","Tempo máx. Resol"],
  "chamados": [ { "Número":"7306", "Tipo":"Publico" } ],
  "fluxos": [ { "projeto":"Serviços","fluxo":"Serviços/Pesquisar cliente","stage":"Prod",
                "execucoes":97038,"requests":776384,"trafegoBytes":4753042813 } ]
}
```

- `\r` na `capaTexto` = quebra de linha dentro da caixa de texto.
- `chamados`/`chamadosColunas` são opcionais (sem MCP do Movidesk). Ausentes → slide de Suporte marcado como pendente.
- `faturamento` é sempre derivável do nosso próprio cálculo, então deve sempre vir.

## Especificação visual da lâmina

Derivada do slide 6 do deck de junho/2026 (exportado e inspecionado, não desenhado de memória):

- Colunas, nesta ordem: **PROJETO | FLUXO | STAGE | EXECUÇÕES | REQUESTS | TRÁFEGO**
- Cabeçalho em maiúsculas, cinza (~#8C8C8C), sem negrito, sem preenchimento
- Linhas com faixa zebrada alternada, sem bordas
- As três últimas colunas alinhadas à direita; as três primeiras à esquerda
- **Ordenação: `requests` decrescente** — é como a tela da plataforma ordena
- 20 itens por lâmina; nº de lâminas = `teto(linhas ÷ 20)`
- Fonte Segoe UI

Diferença conhecida em relação ao print original: a tela tem ícones de "abrir em nova aba" ao lado de PROJETO, FLUXO, EXECUÇÕES e REQUESTS. São elementos de interface, não dado, e não são reproduzidos. **Mostrar para a Vanessa antes da primeira entrega ao cliente.**

## Mecânica de COM — o que quebra e por quê

O ambiente não tem Node nem Python, e não há renderizador de HTML. Excel/PowerPoint COM (servidos pelo WPS Office) são a única via. Cada item abaixo custou um ciclo de depuração:

1. **`Range.Value2` só aceita String no WPS.** Passar `Int32` lança `InvalidCastException`. Pré-formate os números como texto pt-BR — o que dá controle exato sobre a aparência, então não é perda.

2. **`Worksheet.ChartObjects` é property parametrizada**: use `$ws.ChartObjects()` com parênteses. Sem eles o PowerShell devolve um `PSMethod` e `.Add()` não existe.

3. **`CopyPicture` precisa ser `(xlPrinter=2, xlPicture=-4147)`.**
   - `(xlScreen=1, xlBitmap=2)` recorta a imagem no tamanho da janela invisível do Excel — sai um pedaço da tabela.
   - `(xlPrinter=2, xlBitmap=2)` lança "O valor não recai no intervalo esperado".

4. **`Chart.Paste()` estica a imagem para preencher o chart.** Crie o `ChartObject` com a largura e altura **exatas** do range; qualquer diferença vira distorção ou corte.

5. **Nunca retorne um `Range` de uma função PowerShell.** `Range` implementa `IEnumerable`, e o PowerShell desenrola o valor de retorno numa **array de células**. O sintoma é `Não é possível converter "System.Object[]" no tipo "System.Double"` ao ler `.Width`. Construa o range inline em cada chamador.

6. **Chamadas COM vazam valores no pipeline** (`CopyPicture`, `Export`, `Delete` imprimem `True`). Encerre com `| Out-Null` ou o retorno da sua função vira array.

7. **Não cole ranges do Excel direto no PowerPoint.** `Shapes.Paste()` e `Shapes.PasteSpecial()` no WPS colam o formato **texto** (shape tipo 17) e ignoram o `dataType` pedido. Passe por PNG.

8. **Não leia dimensões de shape do COM para calcular proporção.** O WPS devolve tipos inconsistentes em `Shape.Width`/`Height` dependendo de como o shape nasceu. Meça o PNG com `System.Drawing.Image`.

9. **Encaixe a imagem na caixa preservando a proporção.** Forçar a largura em 930 pt faz a imagem transbordar o slide quando a tabela tem muitas linhas (uma tabela de 21 linhas tem proporção ~2.0; o slide disponível pede ~2.4). Use `scale = min(boxW/pw, boxH/ph)`.

10. **Resolução:** o `Chart.Export` sai a 96 DPI, então a tabela é montada maior que o tamanho final (fonte 18 pt, altura de linha 26 pt) para que a redução deixe o texto nítido em vez de borrado. A razão fonte/altura-de-linha também define a proporção da imagem.

11. **A faixa zebrada não está saindo na lâmina final — pendência aberta.** `Interior.Color` é aplicado nas linhas alternadas, mas a banda não aparece no PNG exportado, nem com `#F5F5F5` nem com `#EBEBEB`. Ainda não sei se o `Chart.Export` do WPS descarta o preenchimento de célula ou se o tom se perde na redução. O print original **tem** banda visível, então isto é uma diferença visual real. Não bloqueia (nenhum dado é afetado), mas resolver antes da primeira entrega ao cliente. Próximo teste: um tom claramente escuro (ex.: `#D9D9D9`) para separar "claro demais" de "preenchimento ignorado".

12. **Sempre `Close`/`Quit` em `finally` + `GC::Collect`.** Instâncias `wps`/`wpp` órfãas travam o `.pptx` de saída. Antes de matar processos, confira `MainWindowTitle`: vazio = automação headless, preenchido = documento aberto por uma pessoa.

## Montagem do PPT

- Os slides são localizados **pelo texto do título** (normalizado sem acentos), não por índice fixo — assim o script sobrevive a um template reordenado.
- Ao trocar textos, o mais específico primeiro: `"TOTAL FINAL DO PERÍODO"` contém `"DO PERÍODO"`.
- Quantidade de lâminas: apaga todas menos uma (o molde), duplica até atingir `teto(linhas ÷ 20)`, então troca a imagem de cada uma.
- Slides 2 e 3: apaga a imagem do mês anterior e põe um aviso vermelho. **Deixar o print antigo é pior que deixar vazio** — um print de junho num extrato de julho pode ser enviado por engano.
