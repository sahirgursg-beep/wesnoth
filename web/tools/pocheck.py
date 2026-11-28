#!/usr/bin/env python3
"""Check translated entries: $variables, {placeholders} and markup tags must match msgid."""
import re, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import potool
VAR = re.compile(r"\$[A-Za-z_][A-Za-z0-9_.]*\|?")
TAG = re.compile(r"</?([a-z]+)[^>]*>")
bad = 0
for path in sys.argv[1:]:
    for e in potool.parse(path)[1:]:
        if e.obsolete or "msgid" not in e.fields or e.fuzzy: continue
        src = e.fields["msgid"]
        for k, v in e.fields.items():
            if not k.startswith("msgstr"): continue
            dst = v
            if not dst: continue
            ref = src
            if k != "msgstr" and k != "msgstr[0]" and "msgid_plural" in e.fields:
                ref = e.fields["msgid_plural"]
            sv, dv = sorted(set(VAR.findall(ref))), sorted(set(VAR.findall(dst)))
            st, dt = sorted(TAG.findall(ref)), sorted(TAG.findall(dst))
            if sv != dv or st != dt:
                bad += 1
                print(f"{path}: {ref[:70]!r}\n   vars {sv} vs {dv} tags {st} vs {dt}")
print("problems:", bad)
