#!/usr/bin/env node
/**
 * Gate de confirmacao da APIPASS (multi-ferramenta).
 *
 * Forca uma confirmacao explicita do usuario antes de qualquer operacao com
 * efeito real sobre um environment: publicar, despublicar ou executar um fluxo de
 * teste.
 *
 * Formatos suportados:
 *   (padrao)   Claude Code, GitHub Copilot CLI e VS Code (formato de hook do Claude):
 *              le { tool_name, tool_input } e devolve
 *              hookSpecificOutput.permissionDecision = "ask".
 *   --cursor   Cursor (evento beforeMCPExecution): le { tool_name, tool_input (string),
 *              mcp_server_name } e devolve { permission: "ask" | "allow" }.
 *
 * Algumas ferramentas (ex. VS Code) ignoram o `matcher` do hooks.json e rodam o
 * hook para TODA tool — por isso o filtro por nome tambem e feito aqui: tools que
 * nao sao operacoes protegidas passam sem decisao (formato padrao) ou com
 * "allow" (Cursor, cujo schema exige uma decisao).
 *
 * Codex e Gemini CLI nao usam este script: o gate e declarativo
 * (approval_mode "prompt" no .codex-plugin/plugin.json e policy "ask_user" no
 * pacote do Gemini).
 */

const OPERACOES = {
  unpublish_flow: 'DESPUBLICAR o fluxo do environment',
  publish_flow: 'PUBLICAR a versao do fluxo no environment',
  run_test_flow: 'EXECUTAR o fluxo de teste no environment (cria execucao real)',
};

const isCursor = process.argv.includes('--cursor');

function operacaoDe(toolName) {
  // Nomes variam por ferramenta: mcp__plugin_x_apipass__publish_flow (Claude),
  // mcp_apipass_publish_flow (VS Code), apipass-publish_flow (Copilot CLI),
  // publish_flow (Cursor). Casamos pelo sufixo; unpublish vem antes de publish.
  return Object.keys(OPERACOES).find((k) => String(toolName || '').endsWith(k));
}

function montarRazao(key, input) {
  const acao = key ? OPERACOES[key] : 'realizar uma operacao com efeito real sobre um environment da APIPASS';
  const alvo = [];
  if (input.flowId) alvo.push(`fluxo ${input.flowId}`);
  const environmentId = input.environmentId || input.stageId;
  if (environmentId) alvo.push(`environment ${environmentId}`);
  if (input.historyId) alvo.push(`versao ${input.historyId}`);
  const detalhe = alvo.length ? ` (${alvo.join(', ')})` : '';
  return `Confirmacao obrigatoria: prestes a ${acao}${detalhe}. Aprove apenas se o environment e o fluxo estiverem corretos.`;
}

function responder(obj) {
  process.stdout.write(JSON.stringify(obj));
  process.exit(0);
}

function ask(reason) {
  if (isCursor) {
    return responder({
      permission: 'ask',
      user_message: reason,
      agent_message: 'Aguardando confirmacao do usuario para uma operacao com efeito real na APIPASS.',
    });
  }
  return responder({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason: reason,
    },
  });
}

function seguir() {
  // Tool nao protegida: nao interfere no fluxo normal de permissoes.
  if (isCursor) return responder({ permission: 'allow' });
  process.exit(0);
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  raw += chunk;
});
process.stdin.on('end', () => {
  let evt;
  try {
    evt = JSON.parse(raw || '{}');
  } catch {
    // Sem payload parseavel: ainda assim pedimos confirmacao (fail-safe).
    return ask('Operacao com efeito real sobre um environment da APIPASS — confirme antes de prosseguir.');
  }

  const toolName = evt.tool_name || evt.toolName || '';
  let input = evt.tool_input ?? evt.toolInput ?? evt.toolArgs ?? {};
  if (typeof input === 'string') {
    try {
      input = JSON.parse(input);
    } catch {
      input = {};
    }
  }

  if (isCursor) {
    const server = String(evt.mcp_server_name || '');
    if (server && !server.toLowerCase().includes('apipass')) return seguir();
  }

  const key = operacaoDe(toolName);
  if (!key) return seguir();
  return ask(montarRazao(key, input || {}));
});
