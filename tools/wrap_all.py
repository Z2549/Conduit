"""把指定文件里剩余的 UI 字面量全部包成 tr(...)，用于整块补翻译。

与 apply_i18n.py 不同，这里不要求词表先有条目：包起来但没翻译的会原样
返回英文，之后往 tools/i18n_zh.json 补条目即可。

    python tools/wrap_all.py --dry  lib/features/settings/presentation/settings_sections.dart
    python tools/wrap_all.py --apply lib/features/settings/presentation/settings_sections.dart
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMPORT = "import 'package:conduit/core/l10n/legacy_tr.dart';"

# 这些位置上的字符串是标识，不是文案
BAD_BEFORE = (
    "ValueKey(",
    "Key(",
    "key:",
    "==",
    "!=",
    "case ",
    "contains(",
    "startsWith(",
    "endsWith(",
    "RegExp(",
    "join(",
    "split(",
    "Uri.parse(",
    "package:",
)


def scan(src):
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            yield ("comment", i, j, src[i:j])
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            yield ("comment", i, j, src[i:j])
            i = j
        elif c == '"':
            # 双引号字符串整体跳过：里面的撇号不能当成字符串起点
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            yield ("str", i, j + 1, src[i:j + 1])
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "'":
                    break
                j += 1
            yield ("str", i, j + 1, src[i:j + 1])
            i = j + 1
        else:
            i += 1


def look(text):
    if len(text) < 3 or len(text) > 400:
        return False
    if "$" in text or "\\" in text:
        return False
    if not re.search(r"[A-Za-z]{2,}", text):
        return False
    if re.fullmatch(r"[a-z0-9_./:#-]+", text):
        return False
    return bool(re.search(r"[A-Z]", text)) or " " in text


def process(path, apply):
    src = open(path, encoding="utf-8").read()
    toks = list(scan(src))
    strings = [t for t in toks if t[0] == "str"]
    comments = [(t[1], t[2]) for t in toks if t[0] == "comment"]

    def in_comment(pos):
        return any(a <= pos < b for a, b in comments)

    edits = []  # (start, end, replacement)
    i = 0
    while i < len(strings):
        _, s, e, text = strings[i]
        if in_comment(s):
            i += 1
            continue
        group = [(s, e, text)]
        j = i + 1
        last = e
        while j < len(strings):
            s2, e2, t2 = strings[j][1], strings[j][2], strings[j][3]
            if src[last:s2].strip() == "" and not in_comment(s2):
                group.append((s2, e2, t2))
                last = e2
                j += 1
            else:
                break
        raw = "".join(g[2] for g in group)
        if "$" in raw or "\\" in raw:
            i = j
            continue
        joined = "".join(g[2][1:-1] for g in group)
        before = src[max(0, s - 24):s]
        tail = src[group[-1][1]:group[-1][1] + 8].lstrip()
        head = src[max(0, s - 160):s]
        ok = (
            look(joined)
            and not before.rstrip().endswith("tr(")
            and not any(before.endswith(b) for b in BAD_BEFORE)
            and not re.search(r"\bconst\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*$", head)
            and not re.search(r"\bstatic\s+const\b[^;]{0,80}$", head)
            and not tail.startswith("=>")
            and not re.search(r"[A-Za-z_][A-Za-z0-9_]*\s*=\s*$", before)
        )
        if ok:
            start, end = group[0][0], group[-1][1]
            edits.append((start, end, "tr(" + src[start:end] + ")"))
        i = j

    if not edits:
        print(f"{path}: 0")
        return 0
    if apply:
        for start, end, rep in reversed(edits):
            src = src[:start] + rep + src[end:]
        src = drop_dead_const(src)
        if IMPORT not in src:
            src = add_import(src)
        open(path, "w", encoding="utf-8", newline="\n").write(src)
    print(f"{path}: {len(edits)}")
    return len(edits)


def add_import(src):
    lines = src.split("\n")
    target = "package:conduit/core/l10n/legacy_tr.dart"
    for i, line in enumerate(lines):
        if line.strip() == "library;" or line.strip().startswith("library "):
            lines.insert(i + 1, "")
            lines.insert(i + 2, IMPORT)
            return "\n".join(lines)
    last = None
    for i, line in enumerate(lines):
        if not line.startswith("import '"):
            continue
        p = line[len("import '"):].split("'")[0]
        if p.startswith("package:"):
            last = i
            if p > target:
                lines.insert(i, IMPORT)
                return "\n".join(lines)
    if last is not None:
        lines.insert(last + 1, IMPORT)
    else:
        lines.insert(0, IMPORT)
    return "\n".join(lines)


def drop_dead_const(src):
    """删掉现在含 tr( 的 const（括号/方括号配对后判断）。"""
    import re as _re

    def expr_end(s, start):
        depth = 0
        i = start
        quote = None
        while i < len(s):
            ch = s[i]
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

    out = src
    while True:
        changed = False
        for m in _re.finditer(r"\bconst\s+", out):
            start = m.end()
            while start < len(out) and out[start] in " \t\n":
                start += 1
            name = _re.match(r"[A-Za-z_][A-Za-z0-9_]*", out[start:])
            if name and not out[start + name.end():start + name.end() + 1].strip().startswith(("(", "[", "<")):
                continue
            end = expr_end(out, start)
            if "tr(" in out[start:end]:
                out = out[:m.start()] + out[m.end():]
                changed = True
                break
        if not changed:
            return out


def main():
    apply = "--apply" in sys.argv
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    total = 0
    for p in paths:
        total += process(p, apply)
    print("total", total)


main()
