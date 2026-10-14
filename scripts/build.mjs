#!/usr/bin/env node
/**
 * Build/validacao multi-ferramenta do APIPASS Headless.
 *
 * Fonte unica: plugins/apipass-integrations/ (skills, agents, hooks, .mcp.json) +
 * a versao em plugins/apipass-integrations/.claude-plugin/plugin.json.
 *
 * O script:
 *   1. sincroniza a versao em todos os manifestos (Claude, Codex, Cursor, Copilot, Gemini);
 *   2. gera .github/plugin/marketplace.json (Copilot) a partir do marketplace do Claude;
 *   3. valida skills (frontmatter, nome = diretorio, descricao <= 1024, sem referencias
 *      exclusivas do Claude) e os JSON dos manifestos;
 *   4. monta o pacote do Gemini CLI em dist/gemini/apipass-integrations/ (o Gemini exige o
 *      gemini-extension.json na raiz do pacote) e, com --pack, gera o .tar.gz de release.
 *
 * Uso:
 *   node scripts/build.mjs           # sincroniza + valida + monta dist/gemini
 *   node scripts/build.mjs --check   # so valida; falha se algo estiver dessincronizado (CI)
 *   node scripts/build.mjs --pack    # tambem gera dist/apipass-integrations.tar.gz
 *
 * Sem dependencias: Node >= 18.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync, cpSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const PLUGIN = join(ROOT, 'plugins', 'apipass-integrations');
const GEMINI_ADAPTER = join(ROOT, 'adapters', 'gemini');
const DIST = join(ROOT, 'dist');
const GEMINI_DIST = join(DIST, 'gemini', 'apipass-integrations');

const args = new Set(process.argv.slice(2));
const CHECK = args.has('--check');
const PACK = args.has('--pack');

const errors = [];
const drift = [];
const rel = (p) => relative(ROOT, p);

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    errors.push(`${rel(path)}: JSON invalido (${err.message})`);
    return null;
  }
}

function writeJsonIfChanged(path, data) {
  const next = JSON.stringify(data, null, 2) + '\n';
  const prev = existsSync(path) ? readFileSync(path, 'utf8') : null;
  if (prev === next) return;
  if (CHECK) {
    drift.push(rel(path));
    return;
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, next);
  console.log(`  atualizado: ${rel(path)}`);
}

// --- Frontmatter YAML minimo (chaves de 1o nivel; suporta escalares |, > e inline) ---
function parseFrontmatter(text, path) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) {
    errors.push(`${rel(path)}: sem frontmatter YAML`);
    return null;
  }
  const lines = m[1].split(/\r?\n/);
  const out = {};
  for (let i = 0; i < lines.length; i++) {
    const kv = lines[i].match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!kv) continue;
    const [, key, rawVal] = kv;
    let val = rawVal.trim();
    if (/^[|>][+-]?$/.test(val)) {
      const block = [];
      while (i + 1 < lines.length && (/^\s+\S/.test(lines[i + 1]) || lines[i + 1].trim() === '')) {
        block.push(lines[++i].replace(/^\s{2}/, ''));
      }
      val = val.startsWith('|') ? block.join('\n').trim() : block.join(' ').replace(/\s+/g, ' ').trim();
    } else if (/^(['"]).*\1$/.test(val)) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return { data: out, body: text.slice(m[0].length) };
}

// --- 1. Versao (fonte: .claude-plugin/plugin.json) ---
const claudePluginPath = join(PLUGIN, '.claude-plugin', 'plugin.json');
const claudePlugin = readJson(claudePluginPath);
const version = claudePlugin?.version;
if (!version) errors.push(`${rel(claudePluginPath)}: campo "version" ausente`);
console.log(`APIPASS Headless — versao ${version}`);

const manifests = [
  { path: join(PLUGIN, '.codex-plugin', 'plugin.json'), set: (d) => (d.version = version) },
  { path: join(PLUGIN, '.cursor-plugin', 'plugin.json'), set: (d) => (d.version = version) },
  { path: join(GEMINI_ADAPTER, 'gemini-extension.json'), set: (d) => (d.version = version) },
  {
    path: join(ROOT, '.claude-plugin', 'marketplace.json'),
    set: (d) => d.plugins.forEach((p) => p.name === 'apipass-integrations' && (p.version = version)),
  },
  {
    path: join(ROOT, '.cursor-plugin', 'marketplace.json'),
    set: (d) => ((d.metadata ??= {}).version = version),
  },
];
for (const { path, set } of manifests) {
  const data = readJson(path);
  if (!data) continue;
  if (data.name && !['apipass-integrations', 'apipass-plugins'].includes(data.name)) {
    errors.push(`${rel(path)}: name inesperado "${data.name}"`);
  }
  set(data);
  writeJsonIfChanged(path, data);
}

// --- 2. Marketplace do Copilot (.github/plugin/marketplace.json) = copia do Claude ---
const claudeMarketplace = readJson(join(ROOT, '.claude-plugin', 'marketplace.json'));
if (claudeMarketplace) {
  if (!CHECK) {
    claudeMarketplace.plugins.forEach((p) => p.name === 'apipass-integrations' && (p.version = version));
  }
  writeJsonIfChanged(join(ROOT, '.github', 'plugin', 'marketplace.json'), claudeMarketplace);
}

// --- 3. Validacao ---
for (const p of [join(PLUGIN, '.mcp.json'), join(PLUGIN, 'hooks', 'hooks.json'), join(PLUGIN, 'hooks', 'cursor-hooks.json')]) {
  readJson(p);
}
if (!existsSync(join(PLUGIN, 'hooks', 'confirm-publish.js'))) errors.push('hooks/confirm-publish.js ausente');

const CLAUDE_ONLY = [
  { re: /\/apipass-integrations:[a-z-]+/, msg: 'use "skill `nome`" em vez do comando /apipass-integrations:nome (exclusivo do Claude)' },
  { re: /\bdelegue ao subagent\b/, msg: 'condicione o uso de subagentes ("se a sua ferramenta suportar subagentes")' },
];
const skillsDir = join(PLUGIN, 'skills');
const skills = readdirSync(skillsDir).filter((d) => statSync(join(skillsDir, d)).isDirectory());
for (const dir of skills) {
  const path = join(skillsDir, dir, 'SKILL.md');
  if (!existsSync(path)) {
    errors.push(`${rel(join(skillsDir, dir))}: sem SKILL.md`);
    continue;
  }
  const text = readFileSync(path, 'utf8');
  const fm = parseFrontmatter(text, path);
  if (!fm) continue;
  const { name, description } = fm.data;
  if (name !== dir) errors.push(`${rel(path)}: name "${name}" deve ser igual ao diretorio "${dir}"`);
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name || '') || name.length > 64) errors.push(`${rel(path)}: name invalido (kebab-case, <= 64)`);
  if (!description) errors.push(`${rel(path)}: description vazia`);
  else if (description.length > 1024) errors.push(`${rel(path)}: description com ${description.length} caracteres (max 1024)`);
  for (const { re, msg } of CLAUDE_ONLY) if (re.test(text)) errors.push(`${rel(path)}: ${msg}`);
}
console.log(`  ${skills.length} skills validadas`);

// --- 4. Pacote do Gemini CLI ---
// Converte os subagentes (formato Claude) para o formato do Gemini: tools MCP
// mcp__plugin_apipass-integrations_apipass__X -> mcp_apipass_X.
function toGeminiAgent(text, path) {
  const fm = parseFrontmatter(text, path);
  if (!fm) return null;
  const tools = (fm.data.tools || '')
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => t.replace(/^mcp__(?:plugin_[^_]+(?:_[^_]+)*?_)?apipass__/, 'mcp_apipass_'));
  const yamlStr = (s) => JSON.stringify(s);
  const head = ['---', `name: ${fm.data.name}`, `description: ${yamlStr(fm.data.description)}`];
  if (tools.length) head.push('tools:', ...tools.map((t) => `  - ${t}`));
  head.push('---', '');
  return head.join('\n') + fm.body;
}

if (!CHECK && errors.length === 0) {
  rmSync(GEMINI_DIST, { recursive: true, force: true });
  mkdirSync(GEMINI_DIST, { recursive: true });
  cpSync(join(GEMINI_ADAPTER, 'gemini-extension.json'), join(GEMINI_DIST, 'gemini-extension.json'));
  cpSync(join(GEMINI_ADAPTER, 'GEMINI.md'), join(GEMINI_DIST, 'GEMINI.md'));
  cpSync(join(GEMINI_ADAPTER, 'policies'), join(GEMINI_DIST, 'policies'), { recursive: true });
  cpSync(skillsDir, join(GEMINI_DIST, 'skills'), { recursive: true });
  cpSync(join(ROOT, 'LICENSE'), join(GEMINI_DIST, 'LICENSE'));
  const agentsDir = join(PLUGIN, 'agents');
  if (existsSync(agentsDir)) {
    mkdirSync(join(GEMINI_DIST, 'agents'), { recursive: true });
    for (const f of readdirSync(agentsDir).filter((f) => f.endsWith('.md'))) {
      const converted = toGeminiAgent(readFileSync(join(agentsDir, f), 'utf8'), join(agentsDir, f));
      if (converted) writeFileSync(join(GEMINI_DIST, 'agents', f), converted);
    }
  }
  console.log(`  pacote Gemini: ${rel(GEMINI_DIST)}`);

  if (PACK) {
    const tarball = join(DIST, 'apipass-integrations.tar.gz');
    execFileSync('tar', ['-czf', tarball, '-C', GEMINI_DIST, '.']);
    console.log(`  release Gemini: ${rel(tarball)}`);
  }
}

if (drift.length) errors.push(`arquivos dessincronizados (rode "node scripts/build.mjs"): ${drift.join(', ')}`);
if (errors.length) {
  console.error('\nFalhas:');
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log(CHECK ? 'OK (check)' : 'OK');
