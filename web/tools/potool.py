#!/usr/bin/env python3
"""Small helper to translate Wesnoth .po files without gettext tools.

  potool.py todo  <file.po> [--limit N] [--offset N]
      Print untranslated and fuzzy entries as JSON: key, msgctxt, msgid,
      msgid_plural, the current (fuzzy) translation and the previous msgid.

  potool.py apply <file.po> <translations.json>
      translations.json maps key -> translation (string), or for plural
      entries key -> [singular, plural]. The entry's msgstr is replaced and
      its fuzzy flag and previous-msgid ("#|") comments are dropped.

  potool.py stats <file.po>

Entries are identified by "key": msgctxt + "\\x04" + msgid (like gettext).
Everything else in the file is kept byte for byte.
"""
import json
import sys


def unquote(s):
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s
    out, i, body = [], 0, s[1:-1]
    esc = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "r": "\r"}
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            out.append(esc.get(body[i + 1], "\\" + body[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def quote_lines(keyword, text):
    """gettext style: long or multi-line strings start with "" and wrap at \\n."""
    esc = text.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
    parts = esc.split("\n")
    chunks = [p + "\\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])
    if len(chunks) <= 1 and len(keyword) + len(esc) < 78:
        return ['%s "%s"' % (keyword, chunks[0] if chunks else "")]
    lines = ['%s ""' % keyword]
    for chunk in chunks:
        # wrap long lines at spaces, about 76 characters
        while len(chunk) > 76:
            cut = chunk.rfind(" ", 0, 76)
            if cut <= 0:
                break
            lines.append('"%s"' % chunk[: cut + 1])
            chunk = chunk[cut + 1:]
        lines.append('"%s"' % chunk)
    return lines


class Entry:
    def __init__(self, lines):
        self.lines = lines
        self.fields = {}
        self.flags = []
        self.prev = []
        self.obsolete = all(l.startswith("#~") for l in lines if l.strip())
        current = None
        for l in lines:
            if l.startswith("#,"):
                self.flags = [f.strip() for f in l[2:].split(",")]
            elif l.startswith("#|"):
                self.prev.append(l)
            elif l.startswith("#"):
                continue
            elif l.startswith('"'):
                self.fields[current] += unquote(l)
            else:
                kw, rest = l.split(" ", 1)
                current = kw
                self.fields[kw] = unquote(rest)

    @property
    def key(self):
        ctx = self.fields.get("msgctxt")
        mid = self.fields.get("msgid", "")
        return (ctx + "\x04" + mid) if ctx is not None else mid

    @property
    def plural(self):
        return "msgid_plural" in self.fields

    @property
    def translated(self):
        if self.plural:
            vals = [v for k, v in self.fields.items() if k.startswith("msgstr[")]
            return bool(vals) and all(vals)
        return bool(self.fields.get("msgstr"))

    @property
    def fuzzy(self):
        return "fuzzy" in self.flags

    def previous_msgid(self):
        text = ""
        for l in self.prev:
            l = l[2:].strip()
            if l.startswith("msgid "):
                text += unquote(l[6:])
            elif l.startswith('"'):
                text += unquote(l)
        return text

    def set_translation(self, value):
        out = []
        for l in self.lines:
            if l.startswith("#|"):
                continue
            if l.startswith("#,"):
                flags = [f for f in self.flags if f != "fuzzy"]
                if flags:
                    out.append("#, " + ", ".join(flags))
                continue
            out.append(l)
        # drop old msgstr lines (and their continuation lines)
        kept, in_msgstr = [], False
        for l in out:
            if l.startswith("msgstr"):
                in_msgstr = True
                continue
            if in_msgstr and l.startswith('"'):
                continue
            in_msgstr = False
            kept.append(l)
        if self.plural:
            if isinstance(value, str):
                value = [value, value]
            for i, v in enumerate(value):
                kept += quote_lines("msgstr[%d]" % i, v)
        else:
            kept += quote_lines("msgstr", value)
        self.lines = kept


def parse(path):
    text = open(path, encoding="utf-8").read()
    blocks, cur = [], []
    for line in text.split("\n"):
        if line.strip() == "":
            if cur:
                blocks.append(cur)
                cur = []
            continue
        cur.append(line)
    if cur:
        blocks.append(cur)
    return [Entry(b) for b in blocks]


def write(path, entries):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n\n".join("\n".join(e.lines) for e in entries) + "\n")


def todo_entries(entries):
    return [e for e in entries[1:] if not e.obsolete and "msgid" in e.fields
            and (e.fuzzy or not e.translated)]


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    entries = parse(path)
    if cmd == "stats":
        live = [e for e in entries[1:] if not e.obsolete]
        todo = todo_entries(entries)
        words = sum(len(e.fields.get("msgid", "").split()) for e in todo)
        print(json.dumps({"entries": len(live), "todo": len(todo),
                          "fuzzy": sum(e.fuzzy for e in todo), "words": words}))
    elif cmd == "todo":
        args = sys.argv[3:]
        limit = int(args[args.index("--limit") + 1]) if "--limit" in args else 10 ** 9
        offset = int(args[args.index("--offset") + 1]) if "--offset" in args else 0
        out = []
        for e in todo_entries(entries)[offset:offset + limit]:
            item = {"key": e.key, "msgid": e.fields.get("msgid")}
            if "msgctxt" in e.fields:
                item["msgctxt"] = e.fields["msgctxt"]
            if e.plural:
                item["msgid_plural"] = e.fields["msgid_plural"]
            if e.fuzzy:
                item["old_translation"] = e.fields.get("msgstr", e.fields.get("msgstr[0]", ""))
                prev = e.previous_msgid()
                if prev:
                    item["old_msgid"] = prev
            out.append(item)
        print(json.dumps(out, ensure_ascii=False, indent=1))
    elif cmd == "apply":
        translations = json.load(open(sys.argv[3], encoding="utf-8"))
        by_key = {e.key: e for e in entries[1:] if not e.obsolete}
        missing = [k for k in translations if k not in by_key]
        if missing:
            sys.exit("unknown keys: %r" % missing[:5])
        for key, value in translations.items():
            by_key[key].set_translation(value)
        write(path, entries)
        print("applied %d translations" % len(translations))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
