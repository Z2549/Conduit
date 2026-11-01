# sheprd on herdr-core: shared documents (contract v1)

The sheprd mods for the Herdr app, the `cards` CLI and Conductore share two
herdr-core documents on each machine. Read them with `doc.get` and write them
with `doc.set` (version-checked) over `hc connect` (JSON-RPC lines on
stdin/stdout), or through the `cards` CLI. A write that loses the race gets
`error.data.kind = "conflict"`: read again and retry.

Addresses: a terminal is `t7` on its own machine. Clients that see several
machines prefix the machine name (`dev/t7`) and strip it when writing to that
machine's document.

## `sheprd-cards`: the card ledger

Written by agents through `cards` (update / ask / decide / done / answers) and
by apps through `cards stage / dismiss / send`.

```json
{
  "v": 1,
  "cards": {
    "t7/SHE-12": {
      "id": "SHE-12", "terminal": "t7",
      "title": "Stripe checkout", "status": "dev", "summary": "…", "link": null,
      "questions": [
        { "n": 1, "text": "Which provider?", "options": ["Stripe", "Multibanco"],
          "recommend": 1, "state": "open", "answer": null, "asked_at": "…" }
      ],
      "decisions": [ { "text": "Use Checkout, not Elements", "at": "…" } ],
      "done": false, "done_at": null, "dismissed": false,
      "writeback": { "ok": true, "message": "wrote SHE-12.md" },
      "created_at": "…", "updated_at": "…"
    }
  },
  "inbox": { "t7": [ { "line": "SHE-12 Q1 (Which provider?) → Stripe", "at": "…", "read": false } ] }
}
```

- `questions[].state`: `open` → `staged` (an app chose an answer) →
  `sending` (claimed by one `cards send`) → `sent` (delivered with
  `hc send`), or `dismissed`. A failed send puts `sending` back to `staged`.
  While `sending`, a question carries `claim` and `claimed_at`; a claim older
  than 120 s belongs to a send that died and may be staged and sent again
  (if that send had already typed the line, the agent gets it twice).
  Clients show `sending` as in progress and never write it themselves.
- Sending joins every staged answer of one terminal into one line, e.g.
  `SHE-12 Q1 (Which provider?) → Stripe · Q2 → "EUR only"`, delivered with
  `hc send <terminal>` and kept in `inbox` until the agent runs `cards answers`.
- `dismissed` hides a card from views until its next update.
- `born` (cards and inbox entries) is the terminal's `created_ms`: when a
  core restart reuses `t7` for a new program, that program's first `cards`
  write drops whatever an older `born` left behind.
- Pruning on every write: done cards 14 days after `done_at`; dismissed cards
  7 days and not-done cards 30 days after `updated_at`; per card all live
  questions plus the last 20 answered, the last 50 decisions; inbox entries
  after 14 days, read ones beyond the last 5. A write that hits herdr-core's
  1 MiB cap prunes hard (no done or dismissed cards, not-done cards older than
  7 days, last 5 answered questions, last 20 decisions, no read entries) and
  is retried once.

## `sheprd-view`: the sidebar layout

Written by the `sheprd-sidebar` mod; read by Conductore. Kept on the machine
the app runs on (the hub), like sheprd's `sidebar.toml`.

```json
{
  "v": 1,
  "projects": [
    { "name": "Conductore", "short": "CO", "pinned": false, "collapsed": false,
      "members": ["dev/Conductore-Mobile"], "match": ["conductore"], "note": null }
  ],
  "hidden": ["dev/w12"],
  "filter": "needs-you",
  "active_only": true,
  "other_collapsed": true,
  "marks": {
    "unread": ["dev/t7"],
    "kept": ["omarchy/t3"],
    "dismissed": ["dev/t9@42"]
  }
}
```

- Same shape as sheprd's `[[group]]` in `sidebar.toml` (imported from it on
  first run). `members` are `machine/<space name>` (`local/` for the hub);
  `match` are case-insensitive substrings of a space's name or folder.
  Members win over rules; the first matching project takes the space; the
  rest go to Other. `short` is the two-letter rail tag.
- `filter`: `needs-you` | `working` | `all`.
- Marks follow sheprd's: `unread` clears on focus; `dismissed` is
  `<address>@<seq>` and lapses when the agent's `seq` moves on; `kept` stays in
  the active view.
- An agent "needs you" when blocked, done, or unread; a working agent with a
  staged-but-unsent answer also counts.

## How Conductore reads them (CON-100000)

Copied from sheprd's `herdr-app/CONTRACT.md` (SHE-100012); the sections above
are that contract. This one is Conductore's side.

- A machine's backend is a per-machine setting, "Agents and terminals":
  Herdr (TUI), sheprd, or Herdr app (hc). Herdr stays the default; herdr and
  sheprd both keep driving the `herdr` CLI. On hc the connect picker's Herdr
  tab becomes "Herdr app" and lists `hc ls --json`; agent monitoring reads the
  same list (only terminals whose program reports an OSC 7501 status count as
  agents).
- Both documents are read with one `hc connect` call (`doc.get` for
  `sheprd-view` and `sheprd-cards`). Conductore never writes them, and never
  reads or writes the app's private `herdr-app` document.
- A missing document (`value: null`), a view that is not `v: 1`, or a failed
  read leaves the terminals in one ungrouped list without cards.
- The phone does not know which space of the Herdr app a terminal sits in,
  so a terminal's folder stands in for the space name when projects are
  assigned: a member `machine/<folder>` (`local/` on the machine itself), or
  a `match` rule found in the folder, the cwd or the terminal's name. Members
  win; the first matching project takes it; the rest is Other.
- Open cards (not done, not dismissed) show on their terminal's row with the
  number of open questions: `open`, `staged` and `sending` all count (none
  has reached the agent yet); `sent` and `dismissed` do not. Conductore never
  writes a question's state, `claim` or `born`. Answering them stays in the agent's terminal or
  in the desktop app for now.
- Not on hc, each shown disabled with its reason in a terminal's actions:
  focusing, splitting or zooming the app's panes, new tabs or spaces, and
  Herdr's prefix keys. hc has no command for the app's layout.
