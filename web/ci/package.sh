#!/usr/bin/env bash
# Assembles the browser site: wesnoth.js/.wasm, index.html and the game data
# packed with Emscripten's file_packager.
#
# The data is split so the title screen appears quickly:
#   core      loaded before the game starts: configuration, UI images, fonts,
#             translations, title screen backgrounds, campaign WML
#   others    fetched in the background once the game runs (unit and terrain
#             images, portraits, story art, sounds, campaign art). The game
#             waits for them before it shows a map (see game_launcher.cpp).
#
# Environment: same as game.sh, plus
#   SITE_DIR   output directory (default: $WORK_DIR/site)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/webbuild}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
SITE_DIR="${SITE_DIR:-$WORK_DIR/site}"
STAGE_DIR="$WORK_DIR/stage"

# shellcheck disable=SC1091
source "$WORK_DIR/emsdk/emsdk_env.sh" >/dev/null
PACKAGER="$EMSDK/upstream/emscripten/tools/file_packager.py"

rm -rf "$SITE_DIR" "$STAGE_DIR"
mkdir -p "$SITE_DIR" "$STAGE_DIR"

# Single player campaigns: everything in data/campaigns except the
# multiplayer World Conquest (which goes into the "extras" package).
CAMPAIGNS=()
for d in "$REPO_DIR"/data/campaigns/*/; do
	n="$(basename "$d")"
	[ "$n" = World_Conquest ] || CAMPAIGNS+=("$n")
done
# Languages shipped besides English.
LANGUAGES=(tr)
# Fonts only needed for Chinese/Japanese/Korean (not shipped yet).
CJK_FONTS=(DroidSansFallbackFull.ttf NotoSansJP-VariableFont_wght.ttf)

PACKAGES=()

# Copy one group of files into the stage. Paths relative to the repo.
# usage: stage <package> <path>...
stage() {
	local name="$1"; shift
	local dir="$STAGE_DIR/$name"
	mkdir -p "$dir"
	for rel in "$@"; do
		[ -e "$REPO_DIR/$rel" ] || continue
		mkdir -p "$dir/$(dirname "$rel")"
		cp -a "$REPO_DIR/$rel" "$dir/$rel"
	done
}

# Pack a staged group into <name>.data/<name>.js.
pack() {
	local name="$1"
	python3 "$PACKAGER" "$SITE_DIR/$name.data" \
		--preload "$STAGE_DIR/$name@/wesnoth" \
		--js-output="$SITE_DIR/$name.js" \
		--use-preload-cache \
		--no-node \
		--exclude '*.xcf' --exclude '*.psd' --exclude '*/.git*'
	PACKAGES+=("$name")
	echo "packed $name: $(du -h "$SITE_DIR/$name.data" | cut -f1)"
}

# --- translations: .po -> translations/<lang>/LC_MESSAGES/<domain>.mo
rm -rf "$REPO_DIR/translations"
for lang in "${LANGUAGES[@]}"; do
	mkdir -p "$REPO_DIR/translations/$lang/LC_MESSAGES"
	for po in "$REPO_DIR"/po/*/"$lang".po; do
		domain="$(basename "$(dirname "$po")")"
		case "$domain" in wesnoth-manpages|wesnoth-manual) continue ;; esac
		msgfmt --check-domain -o "$REPO_DIR/translations/$lang/LC_MESSAGES/$domain.mo" "$po"
	done
	echo "translations/$lang: $(ls "$REPO_DIR/translations/$lang/LC_MESSAGES" | wc -l) domains"
done

# --- core (needed before the title screen)
CORE=(images sounds translations data/COPYING.txt)
for f in "$REPO_DIR"/fonts/*; do
	n="$(basename "$f")"
	case " ${CJK_FONTS[*]} " in *" $n "*) ;; *) CORE+=("fonts/$n") ;; esac
done
for f in "$REPO_DIR"/data/*; do
	n="$(basename "$f")"
	case "$n" in campaigns|core|test|tools) ;; *) CORE+=("data/$n") ;; esac
done
for f in "$REPO_DIR"/data/core/*; do
	n="$(basename "$f")"
	case "$n" in images|music|sounds) ;; *) CORE+=("data/core/$n") ;; esac
done
for n in misc icons flags lobby masks themes items help wesnoth-icon.png; do
	CORE+=("data/core/images/$n")
done
# title screen backgrounds that ship with core
TITLE_BG=(landscape-battlefield.webp landscape-mountains-04.webp landscape-mountains-03.webp
	landscape-bridge_sun.webp landscape-castle.webp swamp-02.jpg wesmere.webp)
for n in "${TITLE_BG[@]}"; do CORE+=("data/core/images/story/$n"); done
# the title screen map itself (data/gui/themes/*/dialogs/title_screen.cfg)
CORE+=(data/core/images/maps/background.webp data/core/images/maps/titlescreen.webp)
# For each campaign only what the campaign list needs: _main.cfg (its
# scenarios are #ifdef'ed and load only when the campaign is played),
# achievements, about, and the images _main.cfg shows (icon, background,
# difficulty pictures). The rest comes in a package per campaign.
for f in "$REPO_DIR"/data/campaigns/*.cfg; do [ -f "$f" ] && CORE+=("data/campaigns/$(basename "$f")"); done
CAMPAIGN_CORE_FILES="$WORK_DIR/campaign-core-files.txt"
python3 - "$REPO_DIR" "${CAMPAIGNS[@]}" > "$CAMPAIGN_CORE_FILES" <<'EOF2'
import os, re, sys
repo, campaigns = sys.argv[1], sys.argv[2:]
for c in campaigns:
    base = "data/campaigns/" + c
    for name in ("_main.cfg", "achievements.cfg", "about.cfg"):
        if os.path.isfile(os.path.join(repo, base, name)):
            print(base + "/" + name)
    text = open(os.path.join(repo, base, "_main.cfg"), encoding="utf-8").read()
    # only images used by the [campaign] tag itself (icon, image, background,
    # difficulty pictures), not story art from macros defined in the file
    m = re.search(r"\[campaign\](.*?)\[/campaign\]", text, re.S)
    block = m.group(1) if m else ""
    for path in sorted(set(re.findall(r"(data/campaigns/[A-Za-z0-9_./-]+\.(?:png|webp|jpg))", block))):
        if "/story/" not in path and os.path.isfile(os.path.join(repo, path)):
            print(path)
EOF2
mapfile -t CAMPAIGN_CORE < "$CAMPAIGN_CORE_FILES"
CORE+=("${CAMPAIGN_CORE[@]}")
echo "campaign files in core: ${#CAMPAIGN_CORE[@]}"
stage core "${CORE[@]}"
# only offer title backgrounds that are in the package
python3 - "$STAGE_DIR/core/data/game_config.cfg" "${TITLE_BG[@]}" <<'EOF'
import re, sys
path, names = sys.argv[1], sys.argv[2:]
cfg = open(path, encoding="utf-8").read()
value = ",".join("data/core/images/story/" + n for n in names)
cfg, n = re.subn(r'game_title_background="[^"]*"', 'game_title_background="%s"' % value, cfg)
assert n == 1, "game_title_background not found"
open(path, "w", encoding="utf-8").write(cfg)
EOF
pack core

# --- background packages, in the order they are fetched
stage terrain data/core/images/terrain data/core/images/maps data/core/images/scenery data/core/images/halo
# already in core
rm -f "$STAGE_DIR/terrain/data/core/images/maps/background.webp" "$STAGE_DIR/terrain/data/core/images/maps/titlescreen.webp"
pack terrain

stage units data/core/images/units data/core/images/unit_env data/core/images/attacks data/core/images/projectiles
pack units

stage portraits data/core/images/portraits
pack portraits

STORY=()
for f in "$REPO_DIR"/data/core/images/story/*; do
	n="$(basename "$f")"
	case " ${TITLE_BG[*]} " in *" $n "*) ;; *) STORY+=("data/core/images/story/$n") ;; esac
done
stage story "${STORY[@]}"
pack story

stage extras data/core/sounds data/campaigns/World_Conquest
rm -rf "$STAGE_DIR/extras/data/campaigns/World_Conquest/music"
pack extras

# --- one package per campaign, fetched when the campaign is started.
#     Music is left out for now.
CAMPAIGN_MAP="$WORK_DIR/campaign-packages.json"
echo "{" > "$CAMPAIGN_MAP"
first=1
for c in "${CAMPAIGNS[@]}"; do
	pkg="campaign-$c"
	stage "$pkg" "data/campaigns/$c"
	rm -rf "$STAGE_DIR/$pkg/data/campaigns/$c/music"
	for f in "${CAMPAIGN_CORE[@]}"; do rm -f "$STAGE_DIR/$pkg/$f"; done
	pack "$pkg"
	id="$(python3 - "$REPO_DIR/data/campaigns/$c/_main.cfg" <<'EOF2'
import re, sys
# the id= directly inside [campaign], not one of a nested tag
depth, inside = 0, False
for line in open(sys.argv[1], encoding="utf-8"):
    s = line.split("#", 1)[0].strip()
    if s == "[campaign]":
        inside, depth = True, 0
        continue
    if not inside:
        continue
    if s == "[/campaign]":
        break
    if re.match(r"^\[/", s):
        depth -= 1
    elif re.match(r"^\[[a-z_+]", s):
        depth += 1
    elif depth == 0:
        m = re.match(r"^id\s*=\s*(.+)$", s)
        if m:
            print(m.group(1).strip().strip('"'))
            break
EOF2
)"
	[ -n "$id" ] || { echo "no campaign id for $c"; exit 1; }
	[ $first = 1 ] || echo "," >> "$CAMPAIGN_MAP"
	printf '  "%s": "%s"' "$id" "$pkg" >> "$CAMPAIGN_MAP"
	first=0
done
printf '\n}\n' >> "$CAMPAIGN_MAP"
cat "$CAMPAIGN_MAP"

# report anything from the shipped folders that ended up in no package
python3 - "$REPO_DIR" "$STAGE_DIR" "${CAMPAIGNS[@]}" <<'EOF'
import os, sys
repo, stage, campaigns = sys.argv[1], sys.argv[2], sys.argv[3:]
packed = set()
for pkg in os.listdir(stage):
    root = os.path.join(stage, pkg)
    for d, _, files in os.walk(root):
        for f in files:
            packed.add(os.path.relpath(os.path.join(d, f), root))
missing = []
for top in ["data/core/images"] + ["data/campaigns/" + c for c in campaigns if c != "World_Conquest"]:
    for d, _, files in os.walk(os.path.join(repo, top)):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), repo)
            if rel not in packed and not rel.endswith((".xcf", ".psd")) and "/music/" not in rel:
                missing.append(rel)
print("files not in any package:", len(missing))
for m in missing[:20]:
    print("  ", m)
EOF

# --- the game itself and the page
cp "$BUILD_DIR/wesnoth.js" "$BUILD_DIR/wesnoth.wasm" "$SITE_DIR/"
python3 - "$REPO_DIR/web/shell/index.html" "$SITE_DIR/index.html" "$CAMPAIGN_MAP" "${PACKAGES[@]}" <<'EOF'
import json, sys
src, dst, campaign_map, packages = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
html = open(src, encoding="utf-8").read()
campaigns = json.load(open(campaign_map))
startup = packages[:1]
background = [p for p in packages[1:] if not p.startswith("campaign-")]
tags = "\n".join('<script src="%s.js"></script>' % p for p in startup)
import os
sizes = {p: os.path.getsize(os.path.join(os.path.dirname(dst), p + ".data")) for p in packages}
config = ("<script>window.wesnothBackgroundPackages = %s;\nwindow.wesnothCampaignPackages = %s;\n"
          "window.wesnothPackageSizes = %s;</script>") % (json.dumps(background), json.dumps(campaigns), json.dumps(sizes))
assert "<!-- PACKAGES -->" in html and "</head>" in html
# the list must exist before the page script runs, so it goes into <head>
html = html.replace("</head>", config + "\n</head>", 1)
open(dst, "w", encoding="utf-8").write(html.replace("<!-- PACKAGES -->", tags))
EOF
cp "$REPO_DIR/COPYING" "$SITE_DIR/COPYING.txt"
touch "$SITE_DIR/.nojekyll"

echo "== site"
du -ah "$SITE_DIR" | sort -h | tail -20
du -sh "$SITE_DIR"
