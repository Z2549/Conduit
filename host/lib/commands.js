'use strict'

// `commands <sessionId>` (capability `commands`, CON-125): the slash
// commands an agent's prompt accepts, for the phone's "/" picker.
//
//   builtin  Claude Code's own commands (a fixed list, one line each)
//   custom   *.md under ~/.claude/commands and <cwd>/.claude/commands; a
//            file in a subfolder is `dir:name`; the description comes from
//            the front matter's `description`, else the first text line
//   skills   ~/.claude/skills/*/SKILL.md and <cwd>/.claude/skills/*/SKILL.md
//            (front matter `name` and `description`)
//
// Read on demand, nothing polled or kept: only the first few KB of each
// regular file are read, at most MAX_FILES files and folders, MAX_DEPTH
// folders deep, for at most TIME_LIMIT_MS; nothing whose real path leaves
// its commands/ or skills/ folder is read. A
// project entry wins over a personal one of the same name, like in Claude
// Code. Agents other than Claude Code get empty lists.

const fs = require('fs')
const os = require('os')
const path = require('path')

const HEAD_BYTES = 4096
const MAX_FILES = 300
const MAX_DEPTH = 3
const DESCRIPTION_MAX = 140
// The whole scan gives up after this long (a slow or odd file system).
const TIME_LIMIT_MS = 1500

// Claude Code's built-in commands (2.1.30x). `menu`: opens a picker or a
// screen in the terminal when given no arguments.
const BUILTIN = [
  ['add-dir', 'Add a working directory'],
  ['agents', 'Manage subagents', true],
  ['clear', 'Start a new conversation (clears the history)'],
  ['compact', 'Compact the conversation, with optional focus instructions'],
  ['config', 'Open settings', true],
  ['context', 'Show what fills the context window'],
  ['cost', 'Show the session\'s token cost'],
  ['doctor', 'Check the Claude Code installation'],
  ['export', 'Export the conversation to a file or the clipboard', true],
  ['help', 'Show help and the available commands'],
  ['hooks', 'Manage hooks', true],
  ['init', 'Write a CLAUDE.md for this project'],
  ['mcp', 'Manage MCP servers', true],
  ['memory', 'Edit CLAUDE.md memory files', true],
  ['model', 'Set the model (no argument: pick one)', true],
  ['permissions', 'View or change permission rules', true],
  ['plugin', 'Manage plugins', true],
  ['pr-comments', 'Show the comments of a pull request'],
  ['release-notes', 'Show the release notes'],
  ['resume', 'Resume an earlier conversation', true],
  ['review', 'Review a pull request'],
  ['rewind', 'Rewind the conversation or code', true],
  ['security-review', 'Security review of the pending changes'],
  ['status', 'Show version, model, account and connectivity', true],
  ['todos', 'List the current todo items'],
  ['usage', 'Show plan usage limits', true]
].map(([name, description, menu]) => menu ? { name, description, menu: true } : { name, description })

// The first HEAD_BYTES of a regular file, else null. Non-blocking open and
// fstat: a FIFO or device planted as a .md file is skipped, never waited on.
function readHead (file) {
  let fd
  try {
    fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NONBLOCK || 0))
    if (!fs.fstatSync(fd).isFile()) return null
    const buf = Buffer.alloc(HEAD_BYTES)
    const n = fs.readSync(fd, buf, 0, HEAD_BYTES, 0)
    return buf.subarray(0, n).toString('utf8')
  } catch {
    return null
  } finally {
    if (fd !== undefined) try { fs.closeSync(fd) } catch {}
  }
}

const unquote = v => {
  const t = v.trim()
  if (t.length >= 2 && ((t[0] === '"' && t.endsWith('"')) || (t[0] === "'" && t.endsWith("'")))) return t.slice(1, -1)
  return t
}

// The top-level `key: value` pairs of a YAML front matter, with `>` and `|`
// block scalars folded to one line. Anything else is ignored.
function frontMatter (text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text)
  if (!m) return { fields: {}, body: text }
  const fields = {}
  const lines = m[1].split(/\r?\n/)
  for (let i = 0; i < lines.length; i++) {
    const kv = /^([A-Za-z_][\w-]*):(.*)$/.exec(lines[i])
    if (!kv) continue
    let value = kv[2].trim()
    if (/^[>|][+-]?$/.test(value) || value === '') {
      const block = []
      while (i + 1 < lines.length && (/^\s/.test(lines[i + 1]) || lines[i + 1] === '')) block.push(lines[++i].trim())
      value = block.join(' ')
    }
    fields[kv[1]] = unquote(value)
  }
  return { fields, body: text.slice(m[0].length) }
}

// One line: collapsed whitespace, cut at DESCRIPTION_MAX.
function oneLine (text) {
  const t = String(text || '').replace(/\s+/g, ' ').trim()
  return t.length > DESCRIPTION_MAX ? t.slice(0, DESCRIPTION_MAX - 1).trimEnd() + '…' : t
}

function firstLine (body) {
  for (const line of body.split(/\r?\n/)) {
    const t = line.replace(/^#+\s*/, '').trim()
    if (t) return t
  }
  return ''
}

const validName = name => /^[\w.:-]+$/.test(name)

// The real path of `file` when it stays under `root` (a real path), else
// null: a symlink pointing outside the folder is not followed.
function inside (file, root) {
  let real
  try { real = fs.realpathSync(file) } catch { return null }
  return real === root || real.startsWith(root + path.sep) ? real : null
}

function realRoot (dir) {
  try { return fs.realpathSync(dir) } catch { return null }
}

const spent = budget => budget.left <= 0 || Date.now() > budget.deadline

// *.md files under dir as [relative path without .md, file].
// Every entry (file or folder) counts against the budget; entries whose
// real path leaves `root` are skipped.
function markdownFiles (dir, root, budget, prefix = [], depth = 0) {
  const out = []
  if (spent(budget)) return out
  budget.left -= 1
  let entries
  try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return out }
  entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
  for (const e of entries) {
    if (spent(budget)) break
    if (e.name.startsWith('.')) continue
    const real = inside(path.join(dir, e.name), root)
    if (!real) continue
    let st
    try { st = fs.statSync(real) } catch { continue }
    if (st.isDirectory()) {
      if (depth < MAX_DEPTH) out.push(...markdownFiles(real, root, budget, [...prefix, e.name], depth + 1))
    } else if (st.isFile() && e.name.endsWith('.md')) {
      budget.left -= 1
      // A skill-shaped folder in commands/ (<dir>/SKILL.md) is `<dir>`.
      const name = e.name === 'SKILL.md' && prefix.length ? prefix : [...prefix, e.name.slice(0, -3)]
      out.push([name, real])
    }
  }
  return out
}

function customCommands (dir, scope, budget) {
  const out = []
  const root = realRoot(dir)
  if (!root) return out
  for (const [parts, file] of markdownFiles(root, root, budget)) {
    const name = parts.join(':')
    if (!validName(name)) continue
    const head = readHead(file)
    if (head === null) continue
    const { fields, body } = frontMatter(head)
    const entry = { name, description: oneLine(fields.description || firstLine(body)), scope }
    if (fields['argument-hint']) entry.argumentHint = oneLine(fields['argument-hint'])
    out.push(entry)
  }
  return out
}

function skills (dir, scope, budget) {
  const out = []
  const root = realRoot(dir)
  if (!root) return out
  let entries
  try { entries = fs.readdirSync(root, { withFileTypes: true }) } catch { return out }
  entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
  for (const e of entries) {
    if (spent(budget)) break
    if (e.name.startsWith('.') || !(e.isDirectory() || e.isSymbolicLink())) continue
    budget.left -= 1
    const file = inside(path.join(root, e.name, 'SKILL.md'), root)
    if (!file) continue
    const head = readHead(file)
    if (head === null) continue
    const { fields } = frontMatter(head)
    const name = fields.name || e.name
    if (!validName(name)) continue
    out.push({ name, description: oneLine(fields.description), scope })
  }
  return out
}

// Project entries first; a personal one with the same name is dropped.
function merge (project, personal) {
  const seen = new Set(project.map(c => c.name))
  return [...project, ...personal.filter(c => !seen.has(c.name))]
}

// The lists for an agent ({ kind, cwd }); `home` for tests.
function list (agent, { home = os.homedir() } = {}) {
  const kind = (agent && agent.kind) || 'claude'
  if (kind !== 'claude') return { kind, builtin: [], custom: [], skills: [] }
  const budget = { left: MAX_FILES, deadline: Date.now() + TIME_LIMIT_MS }
  const cwd = agent && typeof agent.cwd === 'string' && path.isAbsolute(agent.cwd) ? agent.cwd : null
  const personalDir = path.join(home, '.claude')
  // A session started in the home folder: its "project" folder is the
  // personal one; read it once.
  const projectDir = cwd && path.resolve(cwd, '.claude') !== path.resolve(personalDir) ? path.join(cwd, '.claude') : null
  const custom = merge(
    projectDir ? customCommands(path.join(projectDir, 'commands'), 'project', budget) : [],
    customCommands(path.join(personalDir, 'commands'), 'personal', budget))
  const skillList = merge(
    projectDir ? skills(path.join(projectDir, 'skills'), 'project', budget) : [],
    skills(path.join(personalDir, 'skills'), 'personal', budget))
  return { kind, builtin: BUILTIN, custom, skills: skillList }
}

module.exports = { list, frontMatter, BUILTIN }
