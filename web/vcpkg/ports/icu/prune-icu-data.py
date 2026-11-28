# wesnoth-web: shrinks ICU's prebuilt data (icudt*.dat) for the browser build.
#
# usage: prune-icu-data.py <icupkg> <icudt.dat> <work dir>
#
# Kept: everything that is not locale specific (properties, normalization,
# collation base data, supplemental data, time zones), plus the locales
# root, en* and tr* (the languages the browser build ships).
# Removed: other locales, charset converters (*.cnv; UTF-8/16 are built in),
# break iterator dictionaries and transliterators -- unless something that is
# kept depends on them (icupkg checks that), in which case they stay.
import os
import re
import subprocess
import sys

KEEP_LANGUAGES = {"en", "tr"}

icupkg, data_file, work = sys.argv[1:4]
items_file = os.path.join(work, "icudata-items.txt")
remove_file = os.path.join(work, "icudata-remove.txt")
pruned_file = os.path.join(work, "icudata-pruned.dat")

subprocess.run([icupkg, "-l", "-o", items_file, data_file], check=True)
items = [line.strip() for line in open(items_file, encoding="utf-8") if line.strip()]


def removable(item):
    path = re.sub(r"^icudt\d+[lbe]/", "", item)
    base = path.rsplit("/", 1)[-1]
    if path.endswith((".cnv", ".dict")) or path.startswith("translit/"):
        return True
    m = re.match(r"^([a-z]{2,3})(_[A-Za-z0-9]*)*\.res$", base)
    return bool(m) and base not in ("pool.res", "root.res") and m.group(1) not in KEEP_LANGUAGES


remove = {item for item in items if removable(item)}
for attempt in range(20):
    with open(remove_file, "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(remove)) + "\n")
    if os.path.exists(pruned_file):
        os.remove(pruned_file)
    proc = subprocess.run([icupkg, "-r", remove_file, data_file, pruned_file],
                          capture_output=True, text=True)
    if proc.returncode == 0:
        break
    needed = set(re.findall(r"depends on missing item (\S+)", proc.stderr + proc.stdout))
    # icupkg prints names without the tree prefix; match both spellings
    keep = {i for i in remove if re.sub(r"^icudt\d+[lbe]/", "", i) in needed or i in needed}
    if not keep:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit("icupkg failed and reported no missing dependencies")
    print("attempt %d: keeping %d items others depend on" % (attempt + 1, len(keep)))
    remove -= keep
else:
    sys.exit("could not resolve ICU data dependencies")

os.replace(pruned_file, data_file)
print("removed %d of %d items" % (len(remove), len(items)))
