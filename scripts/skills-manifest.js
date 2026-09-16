#!/usr/bin/env node
/**
 * Gera (ou verifica) o manifesto das skills do plugin apipass-integrations.
 *
 * Le o frontmatter YAML de cada `plugins/apipass-integrations/skills/<nome>/SKILL.md`
 * e escreve `plugins/apipass-integrations/skills/index.json` com um array de
 * `{ name, description, path }`, ordenado por `name`. O `path` e relativo a raiz
 * do repositorio (POSIX), para que consumidores (ex. `load_skill` do servidor MCP)
 * consigam buscar o arquivo direto numa tag do GitHub.
 *
 * Node puro, sem dependencias. O parser de frontmatter cobre o subconjunto de
 * YAML usado nas skills: escalares simples, strings com aspas simples/duplas e
 * blocos `|` (literal) e `>` (dobrado).
 *
 * Uso:
 *   node scripts/skills-manifest.js          # gera/atualiza index.json
 *   node scripts/skills-manifest.js --check  # falha (exit 1) se index.json estiver desatualizado
 */

'use strict';

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const SKILLS_DIR = path.join(REPO_ROOT, 'plugins', 'apipass-integrations', 'skills');
const OUTPUT_FILE = path.join(SKILLS_DIR, 'index.json');

/** Converte um caminho absoluto em relativo a raiz do repo, com separador POSIX. */
function toRepoPath(absolute) {
  return path.relative(REPO_ROOT, absolute).split(path.sep).join('/');
}

/** Remove aspas de um escalar YAML (simples com '' escapado, ou duplas com escapes basicos). */
function unquote(raw) {
  const value = raw.trim();
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1).replace(/''/g, "'");
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value
      .slice(1, -1)
      .replace(/\\n/g, '\n')
      .replace(/\\t/g, '\t')
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
  }
  return value;
}

/**
 * Le um bloco escalar (`|` ou `>`) a partir da linha `start`.
 * Devolve { value, next } onde `next` e o indice da primeira linha fora do bloco.
 */
function readBlockScalar(lines, start, indicator) {
  const body = [];
  let i = start;
  let indent = null;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === '') {
      body.push('');
      i += 1;
      continue;
    }
    const currentIndent = line.match(/^ */)[0].length;
    if (indent === null) {
      if (currentIndent === 0) break;
      indent = currentIndent;
    }
    if (currentIndent < indent) break;
    body.push(line.slice(indent));
    i += 1;
  }
  // Remove linhas em branco finais (comportamento "clip" do YAML).
  while (body.length && body[body.length - 1] === '') body.pop();

  let value;
  if (indicator === '|') {
    value = body.join('\n');
  } else {
    // Dobrado: quebras simples viram espaco; linha em branco vira quebra de paragrafo.
    value = body
      .reduce((acc, line) => {
        if (line === '') return `${acc}\n`;
        if (acc === '' || acc.endsWith('\n')) return `${acc}${line}`;
        return `${acc} ${line}`;
      }, '')
      .trim();
  }
  return { value, next: i };
}

/** Extrai o frontmatter (entre os dois primeiros `---`) como objeto chave -> string. */
function parseFrontmatter(content, file) {
  const normalized = content.replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) {
    throw new Error(`${toRepoPath(file)}: SKILL.md deve comecar com frontmatter (---)`);
  }
  const end = normalized.indexOf('\n---', 4);
  if (end === -1) {
    throw new Error(`${toRepoPath(file)}: frontmatter sem fechamento (---)`);
  }
  const lines = normalized.slice(4, end).split('\n');
  const result = {};
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === '' || line.trim().startsWith('#')) {
      i += 1;
      continue;
    }
    const match = line.match(/^([A-Za-z0-9_-]+):(.*)$/);
    if (!match) {
      throw new Error(`${toRepoPath(file)}: linha de frontmatter nao reconhecida: "${line}"`);
    }
    const key = match[1];
    const rest = match[2].trim();
    if (rest === '|' || rest === '>' || rest === '|-' || rest === '>-') {
      const block = readBlockScalar(lines, i + 1, rest[0]);
      result[key] = block.value;
      i = block.next;
    } else {
      result[key] = unquote(rest);
      i += 1;
    }
  }
  return result;
}

/** Monta o manifesto em memoria a partir dos SKILL.md. */
function buildManifest() {
  if (!fs.existsSync(SKILLS_DIR)) {
    throw new Error(`Diretorio de skills nao encontrado: ${toRepoPath(SKILLS_DIR)}`);
  }
  const files = fs
    .readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(SKILLS_DIR, entry.name, 'SKILL.md'))
    .filter((file) => fs.existsSync(file));

  const manifest = files.map((file) => {
    const fm = parseFrontmatter(fs.readFileSync(file, 'utf8'), file);
    const dirName = path.basename(path.dirname(file));
    if (!fm.name) throw new Error(`${toRepoPath(file)}: frontmatter sem "name"`);
    if (!fm.description) throw new Error(`${toRepoPath(file)}: frontmatter sem "description"`);
    if (fm.name !== dirName) {
      throw new Error(`${toRepoPath(file)}: "name" (${fm.name}) difere do nome da pasta (${dirName})`);
    }
    return { name: fm.name, description: fm.description, path: toRepoPath(file) };
  });

  manifest.sort((a, b) => a.name.localeCompare(b.name, 'en'));
  return manifest;
}

function serialize(manifest) {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

function main() {
  const check = process.argv.includes('--check');
  const expected = serialize(buildManifest());
  const count = JSON.parse(expected).length;

  if (check) {
    const current = fs.existsSync(OUTPUT_FILE)
      ? fs.readFileSync(OUTPUT_FILE, 'utf8').replace(/\r\n/g, '\n')
      : null;
    if (current !== expected) {
      console.error(
        `${toRepoPath(OUTPUT_FILE)} esta desatualizado. Rode "npm run skills:manifest" e commite o resultado.`,
      );
      process.exit(1);
    }
    console.log(`${toRepoPath(OUTPUT_FILE)} esta atualizado (${count} skills).`);
    return;
  }

  fs.writeFileSync(OUTPUT_FILE, expected, 'utf8');
  console.log(`${toRepoPath(OUTPUT_FILE)} gerado com ${count} skills.`);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
