#!/usr/bin/env node
/**
 * PreToolUse gate da APIPASS.
 *
 * Forca uma confirmacao explicita do usuario antes de qualquer operacao com
 * efeito real sobre um environment: publicar, despublicar ou executar um fluxo de
 * teste. Sempre devolve `permissionDecision: "ask"`, independentemente de
 * allowlist/permissoes — o usuario tem que aprovar manualmente.
 *
 * Le o evento PreToolUse via stdin (JSON com tool_name + tool_input) e monta
 * uma razao que nomeia a operacao e o environment alvo.
 */

const OPERACOES = {
  publish_flow: 'PUBLICAR a versao do fluxo no environment',
  unpublish_flow: 'DESPUBLICAR o fluxo do environment',
  run_test_flow: 'EXECUTAR o fluxo de teste no environment (cria execucao real)',
};

function ask(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'ask',
        permissionDecisionReason: reason,
      },
    }),
  );
  process.exit(0);
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  raw += chunk;
});
process.stdin.on('end', () => {
  let toolName = '';
  let input = {};
  try {
    const evt = JSON.parse(raw || '{}');
    toolName = evt.tool_name || '';
    input = evt.tool_input || {};
  } catch {
    // Sem payload parseavel: ainda assim pedimos confirmacao (fail-safe).
    return ask('Operacao com efeito real sobre um environment da APIPASS — confirme antes de prosseguir.');
  }

  // Resolve qual operacao a partir do sufixo do nome da tool MCP.
  const key = Object.keys(OPERACOES).find((k) => toolName.endsWith(k));
  const acao = key ? OPERACOES[key] : 'realizar uma operacao com efeito real sobre um environment da APIPASS';

  const alvo = [];
  if (input.flowId) alvo.push(`fluxo ${input.flowId}`);
  const environmentId = input.environmentId || input.stageId;
  if (environmentId) alvo.push(`environment ${environmentId}`);
  if (input.historyId) alvo.push(`versao ${input.historyId}`);

  const detalhe = alvo.length ? ` (${alvo.join(', ')})` : '';
  ask(`Confirmacao obrigatoria: prestes a ${acao}${detalhe}. Aprove apenas se o environment e o fluxo estiverem corretos.`);
});
