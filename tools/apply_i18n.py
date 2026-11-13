"""Wrap UI literals in `tr()` and generate the English→Chinese table.

The app was written with English literals in 160+ widgets. Rewriting them to
`context.l10n.key` would mean touching every constructor signature; instead
`tr('Save')` looks the English text up at runtime, and this script does the
mechanical wrapping so a human only reviews translations.

Usage:
    python tools/apply_i18n.py            # dry run: report
    python tools/apply_i18n.py --apply    # write the changes
"""

from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "tools", "i18n_zh.json")
NOWRAP = os.path.join(ROOT, "tools", "i18n_nowrap.json")
GENERATED = os.path.join(ROOT, "lib", "core", "l10n", "legacy_zh.dart")
IMPORT = "import 'package:conduit/core/l10n/legacy_tr.dart';"

TEXT_CALL = re.compile(r"""(?P<prefix>const\s+)?Text\(\s*'(?P<body>(?:[^'\\]|\\.){2,})'""")
NAMED = re.compile(
    r"""(?P<name>label|labelText|title|subtitle|hintText|tooltip|semanticLabel|helperText|errorText|description|message|placeholder)\s*:\s*(?P<prefix>const\s+)?'(?P<body>(?:[^'\\]|\\.){2,})'"""
)


def unescape(body: str) -> str:
    return body.replace("\\'", "'").replace("\\\\", "\\")


def load_table() -> dict[str, str]:
    if not os.path.exists(TABLE):
        return {}
    with open(TABLE, encoding="utf-8") as fh:
        return json.load(fh)


def eligible(body: str, table: dict[str, str]) -> bool:
    text = unescape(body)
    if text not in table:
        return False
    if "$" in text:
        return False
    if text.startswith(("http", "package:", "assets/", "conduit/", "hc/", "/", "#")):
        return False
    return True


def load_nowrap() -> dict[str, set[str]]:
    if not os.path.exists(NOWRAP):
        return {}
    with open(NOWRAP, encoding="utf-8") as fh:
        return {k: set(v) for k, v in json.load(fh).items()}


def wrap_file(
    path: str, table: dict[str, str], nowrap: dict[str, set[str]], rel: str
) -> tuple[str, int]:
    src = open(path, encoding="utf-8").read()
    # A `part of` file cannot carry its own imports; it inherits the owner's.
    if re.search(r"^\s*part of\b", src, re.M):
        return src, 0
    count = 0

    def repl_text(m: re.Match[str]) -> str:
        nonlocal count
        text = unescape(m.group("body"))
        if not eligible(m.group("body"), table) or text in nowrap.get(rel, ()):
            return m.group(0)
        count += 1
        return "Text(tr('%s')" % m.group("body")

    def repl_named(m: re.Match[str]) -> str:
        nonlocal count
        text = unescape(m.group("body"))
        if not eligible(m.group("body"), table) or text in nowrap.get(rel, ()):
            return m.group(0)
        count += 1
        return "%s: tr('%s')" % (m.group("name"), m.group("body"))

    src = TEXT_CALL.sub(repl_text, src)
    src = NAMED.sub(repl_named, src)
    if count:
        src = drop_dead_const(src)
        src = ensure_import(src)
    return src, count


def _expression_end(src: str, start: int) -> int:
    """Index just past the balanced expression that begins at *start*."""
    depth = 0
    i = start
    quote = None
    while i < len(src):
        ch = src[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return i + 1
        elif depth == 0 and ch in ",;\n":
            return i
        i += 1
    return i


def drop_dead_const(src: str) -> str:
    """Remove `const` from expressions that now contain a `tr(` call."""
    out = src
    while True:
        changed = False
        for m in re.finditer(r"\bconst\s+", out):
            start = m.end()
            while start < len(out) and out[start] in " \t\n":
                start += 1
            # Skip `const` on declarations (`const foo = ...`).
            name = re.match(r"[A-Za-z_][A-Za-z0-9_]*", out[start:])
            if name and not out[start + name.end() : start + name.end() + 1].strip().startswith(("(", "[", "<")):
                continue
            end = _expression_end(out, start)
            if "tr(" in out[start:end]:
                out = out[: m.start()] + out[m.end() :]
                changed = True
                break
        if not changed:
            return out


def ensure_import(src: str) -> str:
    if IMPORT in src:
        return src
    lines = src.split("\n")
    target = "package:conduit/core/l10n/legacy_tr.dart"
    # A `library` directive must stay first: the import goes right after it.
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "library;" or stripped.startswith("library "):
            lines.insert(i + 1, "")
            lines.insert(i + 2, IMPORT)
            return "\n".join(lines)
    last_package = None
    for i, line in enumerate(lines):
        if not line.startswith("import '"):
            continue
        path = line[len("import '") :].split("'")[0]
        if not path.startswith("package:"):
            continue
        last_package = i
        if path > target:
            lines.insert(i, IMPORT)
            return "\n".join(lines)
    if last_package is not None:
        lines.insert(last_package + 1, IMPORT)
        return "\n".join(lines)
    # Only dart: imports (or none): put it after the last import line.
    last = -1
    for i, line in enumerate(lines):
        if line.startswith("import '"):
            last = i
    if last < 0:
        lines.insert(0, IMPORT)
        lines.insert(1, "")
        return "\n".join(lines)
    lines.insert(last + 1, "")
    lines.insert(last + 2, IMPORT)
    return "\n".join(lines)


def dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("$", "\\$").replace("'", "\\'") + "'"


def write_table(table: dict[str, str]) -> None:
    entries = ",\n".join(
        "  %s: %s" % (dart_string(k), dart_string(v))
        for k, v in sorted(table.items(), key=lambda kv: kv[0].lower())
    )
    body = (
        "/// English to Simplified Chinese for the literals the UI was written with.\n"
        "///\n"
        "/// Generated by tools/apply_i18n.py from tools/i18n_zh.json; edit the\n"
        "/// JSON, not this file.\n"
        "const Map<String, String> legacyZh = <String, String>{\n"
        f"{entries}\n"
        "};\n"
    )
    with open(GENERATED, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(body)


def main() -> None:
    apply = "--apply" in sys.argv
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg.split("=", 1)[1]
    table = load_table()
    nowrap = load_nowrap()
    total = 0
    touched = 0
    for base, _, names in os.walk(os.path.join(ROOT, "lib")):
        for name in names:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if only and not rel.startswith(only):
                continue
            new, count = wrap_file(path, table, nowrap, rel)
            if not count:
                continue
            touched += 1
            total += count
            if apply:
                with open(path, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(new)
    print(f"{'applied' if apply else 'would wrap'}: {total} strings in {touched} files")
    if apply:
        write_table(table)
        print("wrote", os.path.relpath(GENERATED, ROOT))


if __name__ == "__main__":
    main()
