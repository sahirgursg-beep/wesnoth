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

# Campaigns shipped in the preview (small, beginner friendly).
CAMPAIGNS=(Two_Brothers The_South_Guard)
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
# campaign WML, maps and scripts (their art and sounds come later)
for f in "$REPO_DIR"/data/campaigns/*.cfg; do [ -f "$f" ] && CORE+=("data/campaigns/$(basename "$f")"); done
for c in "${CAMPAIGNS[@]}"; do
	for f in "$REPO_DIR/data/campaigns/$c"/*; do
		n="$(basename "$f")"
		case "$n" in images|sounds) ;; *) CORE+=("data/campaigns/$c/$n") ;; esac
	done
done
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

EXTRAS=(data/core/sounds)
for c in "${CAMPAIGNS[@]}"; do EXTRAS+=("data/campaigns/$c/images" "data/campaigns/$c/sounds"); done
stage extras "${EXTRAS[@]}"
pack extras

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
for top in ["data/core/images"] + ["data/campaigns/" + c for c in campaigns]:
    for d, _, files in os.walk(os.path.join(repo, top)):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), repo)
            if rel not in packed and not rel.endswith((".xcf", ".psd")):
                missing.append(rel)
print("files not in any package:", len(missing))
for m in missing[:20]:
    print("  ", m)
EOF

# --- the game itself and the page
cp "$BUILD_DIR/wesnoth.js" "$BUILD_DIR/wesnoth.wasm" "$SITE_DIR/"
python3 - "$REPO_DIR/web/shell/index.html" "$SITE_DIR/index.html" "${PACKAGES[@]}" <<'EOF'
import json, sys
src, dst, packages = sys.argv[1], sys.argv[2], sys.argv[3:]
html = open(src, encoding="utf-8").read()
startup, background = packages[:1], packages[1:]
tags = "\n".join('<script src="%s.js"></script>' % p for p in startup)
config = "<script>window.wesnothBackgroundPackages = %s;</script>" % json.dumps(background)
assert "<!-- PACKAGES -->" in html
open(dst, "w", encoding="utf-8").write(html.replace("<!-- PACKAGES -->", config + "\n" + tags))
EOF
cp "$REPO_DIR/COPYING" "$SITE_DIR/COPYING.txt"
touch "$SITE_DIR/.nojekyll"

echo "== site"
du -ah "$SITE_DIR" | sort -h | tail -20
du -sh "$SITE_DIR"
