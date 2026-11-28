# wesnoth-web: decides which items of ICU's prebuilt data (icudt*.dat) the
# browser build keeps. Reads "icupkg -l" output, prints the items to remove.
#
# Kept: everything that is not locale specific (properties, normalization,
# collation base data, supplemental data, time zones), plus the locales
# root, en* and tr* (the languages the browser build ships).
# Removed: other locales, charset converters (*.cnv; UTF-8/16 are built in),
# break iterator dictionaries (CJK/Thai/...), transliterators.
import re
import sys

KEEP_LANGUAGES = {"en", "tr"}

for line in open(sys.argv[1], encoding="utf-8"):
    item = line.strip()
    if not item:
        continue
    path = re.sub(r"^icudt\d+[lbe]/", "", item)
    base = path.rsplit("/", 1)[-1]
    if path.endswith((".cnv", ".dict")) or path.startswith("translit/"):
        print(item)
        continue
    m = re.match(r"^([a-z]{2,3})(_[A-Za-z0-9]+)*\.res$", base)
    if m and base not in ("pool.res", "root.res") and m.group(1) not in KEEP_LANGUAGES:
        print(item)
