#!/usr/bin/env bash
# Builds the Wesnoth client dependencies for WebAssembly with vcpkg.
#
# Uses vcpkg classic mode with --keep-going so that a single CI run reports
# every failing port at once. Successful ports land in the binary cache
# ($VCPKG_BINARY_CACHE) and are reused by later runs.
#
# Environment:
#   EMSDK_VERSION       emsdk version to install (default: latest)
#   VCPKG_COMMIT        vcpkg commit (default: builtin-baseline of vcpkg.json)
#   WORK_DIR            scratch directory (default: $HOME/webbuild)
#   VCPKG_BINARY_CACHE  binary cache directory (default: $WORK_DIR/vcpkg-bincache)
#   LOG_DIR             where logs are collected (default: $WORK_DIR/logs)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/webbuild}"
EMSDK_VERSION="${EMSDK_VERSION:-latest}"
VCPKG_COMMIT="${VCPKG_COMMIT:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["builtin-baseline"])' "$REPO_DIR/vcpkg.json")}"
VCPKG_BINARY_CACHE="${VCPKG_BINARY_CACHE:-$WORK_DIR/vcpkg-bincache}"
LOG_DIR="${LOG_DIR:-$WORK_DIR/logs}"
TRIPLET=wasm32-emscripten-wesnoth

mkdir -p "$WORK_DIR" "$VCPKG_BINARY_CACHE" "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/deps.log") 2>&1

echo "== emsdk $EMSDK_VERSION"
if [ ! -d "$WORK_DIR/emsdk" ]; then
	git clone --depth 1 https://github.com/emscripten-core/emsdk "$WORK_DIR/emsdk" || exit 1
fi
( cd "$WORK_DIR/emsdk" && ./emsdk install "$EMSDK_VERSION" && ./emsdk activate "$EMSDK_VERSION" ) || exit 1
# shellcheck disable=SC1091
source "$WORK_DIR/emsdk/emsdk_env.sh"
emcc --version | head -1 | tee "$LOG_DIR/emcc-version.txt"

echo "== vcpkg $VCPKG_COMMIT"
if [ ! -x "$WORK_DIR/vcpkg/vcpkg" ]; then
	rm -rf "$WORK_DIR/vcpkg"
	git init -q "$WORK_DIR/vcpkg"
	git -C "$WORK_DIR/vcpkg" fetch -q --depth 1 https://github.com/microsoft/vcpkg "$VCPKG_COMMIT" || exit 1
	git -C "$WORK_DIR/vcpkg" checkout -q FETCH_HEAD || exit 1
	"$WORK_DIR/vcpkg/bootstrap-vcpkg.sh" -disableMetrics || exit 1
fi

mapfile -t PACKAGES < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$REPO_DIR/web/vcpkg/packages.txt" | grep -v '^$')
SPECS=()
for p in "${PACKAGES[@]}"; do
	# attach the triplet: name[features] -> name[features]:triplet
	SPECS+=("$p:$TRIPLET")
done

echo "== vcpkg install (${#SPECS[@]} packages)"
# run outside the source tree, otherwise vcpkg switches to manifest mode
cd "$WORK_DIR" || exit 1
"$WORK_DIR/vcpkg/vcpkg" install \
	--overlay-triplets="$REPO_DIR/web/vcpkg/triplets" \
	--overlay-ports="$REPO_DIR/web/vcpkg/ports" \
	--binarysource="clear;files,$VCPKG_BINARY_CACHE,readwrite" \
	--keep-going \
	--allow-unsupported \
	"${SPECS[@]}" 2>&1 | tee "$LOG_DIR/vcpkg-install.log"
STATUS=${PIPESTATUS[0]}

echo "== collecting logs"
"$WORK_DIR/vcpkg/vcpkg" list > "$LOG_DIR/installed.txt" 2>&1
grep -E "BUILD_FAILED|CASCADED_DUE_TO_MISSING_DEPENDENCIES|failed with" "$LOG_DIR/vcpkg-install.log" | sort -u > "$LOG_DIR/failures.txt"
mkdir -p "$LOG_DIR/ports"
for d in "$WORK_DIR"/vcpkg/buildtrees/*/; do
	port="$(basename "$d")"
	[ "$port" = "detect_compiler" ] && continue
	if ! grep -q "^$port:$TRIPLET" "$LOG_DIR/installed.txt"; then
		mkdir -p "$LOG_DIR/ports/$port"
		for f in "$d"*.log; do
			[ -f "$f" ] || continue
			# compiler/linker errors with some context, from anywhere in the log
			grep -n -B3 -A12 -E "(error|Error|ERROR)[: ]|FAILED:|undefined symbol" "$f" | grep -v "Wcounter-extension" | head -c 200000 \
				> "$LOG_DIR/ports/$port/$(basename "$f" .log)-errors.txt" 2>/dev/null || true
			# keep the end of each log; that is where errors are
			tail -c 150000 "$f" > "$LOG_DIR/ports/$port/$(basename "$f")"
		done
		# meson/cmake configure logs live in subdirectories
		find "$d" -maxdepth 4 \( -name 'meson-log.txt' -o -name 'CMakeConfigureLog.yaml' -o -name 'config.log' \) -print0 2>/dev/null |
			while IFS= read -r -d '' f; do
				tail -c 150000 "$f" > "$LOG_DIR/ports/$port/$(echo "${f#"$d"}" | tr '/' '_')"
			done
	fi
done

echo "vcpkg exit status: $STATUS" | tee "$LOG_DIR/status.txt"
exit "$STATUS"
