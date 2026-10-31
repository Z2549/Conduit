'use strict'

// `commands`' disk scan (CON-125 review): odd files are skipped, never
// waited on, and nothing outside the commands/ and skills/ folders is read.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const { tempDir, cleanup } = require('./helpers/cleanup')
const { list } = require('../lib/commands')

test.after(cleanup)

const w = (f, t) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, t) }

test('a .md that is a FIFO is skipped, not waited on', { timeout: 5000 }, () => {
  const h = tempDir('cnd-cmdf-')
  w(path.join(h, '.claude/commands/ok.md'), 'Fine')
  execFileSync('mkfifo', [path.join(h, '.claude/commands/fifo.md')])
  fs.symlinkSync(path.join(h, '.claude/commands/fifo.md'), path.join(h, '.claude/commands/link.md'))
  const r = list({ kind: 'claude', cwd: null }, { home: h })
  assert.deepEqual(r.custom.map(c => c.name), ['ok'])
})

test('symlinks out of the commands or skills folder are not read', () => {
  const h = tempDir('cnd-cmds-')
  const outside = tempDir('cnd-cmds-out-')
  w(path.join(outside, 'secret.md'), 'TOKEN=hunter2')
  w(path.join(outside, 'skill/SKILL.md'), '---\nname: leak\ndescription: TOKEN=hunter2\n---\n')
  w(path.join(h, '.claude/commands/real.md'), 'Real one')
  fs.symlinkSync(path.join(outside, 'secret.md'), path.join(h, '.claude/commands/secret.md'))
  fs.symlinkSync(outside, path.join(h, '.claude/commands/dir'))
  fs.mkdirSync(path.join(h, '.claude/skills/evil'), { recursive: true })
  fs.symlinkSync(path.join(outside, 'skill/SKILL.md'), path.join(h, '.claude/skills/evil/SKILL.md'))
  // Inside the folder, a symlink is fine.
  fs.symlinkSync(path.join(h, '.claude/commands/real.md'), path.join(h, '.claude/commands/alias.md'))
  const r = list({ kind: 'claude', cwd: null }, { home: h })
  assert.deepEqual(r.custom.map(c => c.name), ['alias', 'real'])
  assert.deepEqual(r.skills, [])
  assert.doesNotMatch(JSON.stringify(r), /hunter2/)
})

test('folders count against the scan budget (commands -> /proc ends quickly)', () => {
  const h = tempDir('cnd-cmdp-')
  fs.mkdirSync(path.join(h, '.claude'), { recursive: true })
  fs.symlinkSync('/proc', path.join(h, '.claude/commands'))
  const t0 = Date.now()
  list({ kind: 'claude', cwd: null }, { home: h })
  assert.ok(Date.now() - t0 < 2500, `took ${Date.now() - t0} ms`)
})

test('commands/<dir>/SKILL.md is listed as <dir>', () => {
  const h = tempDir('cnd-cmdk-')
  w(path.join(h, '.claude/commands/ship/SKILL.md'), '---\ndescription: Ship things\n---\n')
  w(path.join(h, '.claude/commands/a/b/SKILL.md'), 'Nested')
  const r = list({ kind: 'claude', cwd: null }, { home: h })
  assert.deepEqual(r.custom, [
    { name: 'a:b', description: 'Nested', scope: 'personal' },
    { name: 'ship', description: 'Ship things', scope: 'personal' }
  ])
})
