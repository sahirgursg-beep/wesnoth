#!/usr/bin/env bash
# Assembles the browser site: wesnoth.js/.wasm, index.html and the game data
# packed with Emscripten's file_packager (one package per group, each under
# 100MB so they are easy to host and cache).
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

# Campaigns shipped in the first preview (small, beginner friendly).
CAMPAIGNS=(Two_Brothers The_South_Guard)

# Stage a copy of one group of files, then pack it.
# usage: pack <name> <path relative to repo>...
pack() {
	local name="$1"; shift
	local dir="$STAGE_DIR/$name"
	mkdir -p "$dir"
	for rel in "$@"; do
		mkdir -p "$dir/$(dirname "$rel")"
		cp -a "$REPO_DIR/$rel" "$dir/$rel"
	done
	python3 "$PACKAGER" "$SITE_DIR/$name.data" \
		--preload "$dir@/wesnoth" \
		--js-output="$SITE_DIR/$name.js" \
		--use-preload-cache \
		--no-node \
		--exclude '*.xcf' --exclude '*.psd' --exclude '*/.git*'
	echo "packed $name: $(du -h "$SITE_DIR/$name.data" | cut -f1)"
}

# 1. everything except big image folders, music, campaigns, tests and tools
BASE=(fonts images sounds data/COPYING.txt)
for f in "$REPO_DIR"/data/*; do
	n="$(basename "$f")"
	case "$n" in campaigns|core|test|tools) ;; *) BASE+=("data/$n") ;; esac
done
for f in "$REPO_DIR"/data/core/*; do
	n="$(basename "$f")"
	case "$n" in images|music) ;; *) BASE+=("data/core/$n") ;; esac
done
pack base "${BASE[@]}"

# 2. core images, split in two packages
IMG_A=(data/core/images/terrain data/core/images/maps data/core/images/halo)
IMG_B=()
for f in "$REPO_DIR"/data/core/images/*; do
	n="data/core/images/$(basename "$f")"
	case " ${IMG_A[*]} " in *" $n "*) ;; *) IMG_B+=("$n") ;; esac
done
pack images-terrain "${IMG_A[@]}"
pack images-units "${IMG_B[@]}"

# 3. campaigns (needs the campaigns/_main.cfg-style loader files too)
CAMP=()
for f in "$REPO_DIR"/data/campaigns/*.cfg; do [ -f "$f" ] && CAMP+=("data/campaigns/$(basename "$f")"); done
for c in "${CAMPAIGNS[@]}"; do CAMP+=("data/campaigns/$c"); done
pack campaigns "${CAMP[@]}"

# 4. the game itself and the page
cp "$BUILD_DIR/wesnoth.js" "$BUILD_DIR/wesnoth.wasm" "$SITE_DIR/"
TAGS=""
for p in base images-terrain images-units campaigns; do
	TAGS+="<script src=\"$p.js\"></script>"$'\n'
done
python3 - "$REPO_DIR/web/shell/index.html" "$SITE_DIR/index.html" "$TAGS" <<'EOF'
import sys
src, dst, tags = sys.argv[1:4]
html = open(src, encoding="utf-8").read()
assert "<!-- PACKAGES -->" in html
open(dst, "w", encoding="utf-8").write(html.replace("<!-- PACKAGES -->", tags.rstrip()))
EOF
cp "$REPO_DIR/COPYING" "$SITE_DIR/COPYING.txt"
touch "$SITE_DIR/.nojekyll"

echo "== site"
du -ah "$SITE_DIR" | sort -h | tail -20
du -sh "$SITE_DIR"
