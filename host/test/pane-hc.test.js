'use strict'
// Input to an agent in a Herdr app terminal goes through a fake `hc`.
const test = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pane-hc-'))
const calls = path.join(dir, 'calls')
fs.writeFileSync(path.join(dir, 'hc'), `#!/bin/sh
printf '%s\\n' "$*" >> "${calls}"
case "$1" in
  get) [ "$4" = t9 ] && { echo '{"error":{"kind":"not_found","message":"no terminal"}}' >&2; exit 3; }
       [ "$4" = t8 ] && { echo '{"finished_ms":1}'; exit 0; }
       echo '{"finished_ms":null}' ;;
  send) [ "$3" = t7 ] && exit 9; echo '{}' ;;
  read) echo 'the screen' ;;
  *) echo '{}' ;;
esac
`, { mode: 0o755 })
process.env.PATH = `${dir}:${process.env.PATH}`
const pane = require('../lib/pane')

const agent = terminal => ({ sessionId: 's', hc: { terminal }, herdr: null, tmux: null })
const log = () => fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : []
test.beforeEach(() => fs.rmSync(calls, { force: true }))
test.after(() => fs.rmSync(dir, { recursive: true, force: true }))

test('the terminal is the first target', () => {
  assert.deepStrictEqual(pane.targets({ ...agent('t1'), tmux: { paneId: '%1' } }).map(t => t.via), ['hc', 'tmux'])
})

test('a prompt goes with hc send', async () => {
  assert.deepStrictEqual(await pane.sendText(agent('t1'), 'fix the tests\nplease'), { ok: true, via: 'hc', paneId: 't1' })
  assert.deepStrictEqual(log(), ['get --json -- t1', 'send -- t1 fix the tests', 'please'])
})

test('a blocked program stops the send', async () => {
  const r = await pane.sendText(agent('t7'), 'yes')
  assert.match(r.error, /hc send failed/)
})

test('a gone or finished terminal is refused, nothing typed', async () => {
  assert.match((await pane.sendText(agent('t9'), 'x')).error, /is gone/)
  assert.match((await pane.sendText(agent('t8'), 'x')).error, /has finished/)
  assert.ok(log().every(line => line.startsWith('get ')))
})

test('without Enter it goes key by key, ASCII only', async () => {
  assert.ok((await pane.sendText(agent('t1'), 'a b', { enter: false })).ok)
  assert.strictEqual(log().at(-1), 'keys -- t1 a space b')
  assert.match((await pane.sendText(agent('t1'), 'é', { enter: false })).error, /without pressing Enter/)
})

test('Escape and the dialog io use hc', async () => {
  assert.ok((await pane.sendKey(agent('t1'), 'escape')).ok)
  assert.strictEqual(log().at(-1), 'keys -- t1 esc')
  const { io } = await pane.terminalIo(agent('t1'))
  assert.match(await io.read(), /the screen/)
  await io.key('down')
  assert.strictEqual(log().at(-1), 'keys -- t1 down')
})
