#!/usr/bin/env bash
# Configures and compiles the Wesnoth game client for WebAssembly.
# Run after deps.sh (it reuses its emsdk and vcpkg installation).
#
# Uses "ninja -k 0" so one CI run reports every compile error at once.
#
# Environment: same as deps.sh, plus
#   BUILD_DIR   CMake build directory (default: $WORK_DIR/build)
#   GAME_LOG_DIR where logs are collected (default: $WORK_DIR/logs-game)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/webbuild}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
GAME_LOG_DIR="${GAME_LOG_DIR:-$WORK_DIR/logs-game}"
WEB_VARIANT="${WEB_VARIANT:-jspi}"
if [ "$WEB_VARIANT" = asyncify ]; then
	TRIPLET=wasm32-emscripten-wesnoth-asyncify
	WASM_FLAGS="-fexceptions -sSUPPORT_LONGJMP=emscripten"
	ASYNCIFY=ON
else
	TRIPLET=wasm32-emscripten-wesnoth
	WASM_FLAGS="-fwasm-exceptions -sSUPPORT_LONGJMP=wasm"
	ASYNCIFY=OFF
fi
VCPKG_ROOT="$WORK_DIR/vcpkg"

mkdir -p "$GAME_LOG_DIR"

# shellcheck disable=SC1091
source "$WORK_DIR/emsdk/emsdk_env.sh" >/dev/null

# only the wasm .pc files, never the host's
export PKG_CONFIG_LIBDIR="$VCPKG_ROOT/installed/$TRIPLET/lib/pkgconfig:$VCPKG_ROOT/installed/$TRIPLET/share/pkgconfig"
unset PKG_CONFIG_PATH

LAUNCHER=()
if command -v ccache >/dev/null; then
	LAUNCHER=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
	ccache -z >/dev/null
fi

echo "== configure"
cmake -S "$REPO_DIR" -B "$BUILD_DIR" -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
	-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
	-DVCPKG_TARGET_TRIPLET="$TRIPLET" \
	-DVCPKG_OVERLAY_TRIPLETS="$REPO_DIR/web/vcpkg/triplets" \
	-DVCPKG_MANIFEST_MODE=OFF \
	-DVCPKG_INSTALLED_DIR="$VCPKG_ROOT/installed" \
	-DCMAKE_C_FLAGS="$WASM_FLAGS" \
	-DCMAKE_CXX_FLAGS="$WASM_FLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="$WASM_FLAGS" \
	-DWESNOTH_WEB_ASYNCIFY=$ASYNCIFY \
	-DENABLE_GAME=ON \
	-DENABLE_SERVER=OFF \
	-DENABLE_CAMPAIGN_SERVER=OFF \
	-DENABLE_TESTS=OFF \
	-DENABLE_NLS=OFF \
	-DHARDEN=OFF \
	-DENABLE_DESKTOP_ENTRY=OFF \
	-DENABLE_APPDATA_FILE=OFF \
	-DENABLE_DISPLAY_REVISION=OFF \
	"${LAUNCHER[@]}" \
	2>&1 | tee "$GAME_LOG_DIR/configure.log"
STATUS=${PIPESTATUS[0]}

if [ "$STATUS" -eq 0 ]; then
	echo "== build"
	cmake --build "$BUILD_DIR" --target wesnoth -- -k 0 2>&1 | tee "$GAME_LOG_DIR/build.log"
	STATUS=${PIPESTATUS[0]}
fi

echo "== collecting logs"
cp "$BUILD_DIR/CMakeCache.txt" "$GAME_LOG_DIR/CMakeCache.txt" 2>/dev/null || true
[ -f "$BUILD_DIR/CMakeFiles/CMakeConfigureLog.yaml" ] && tail -c 300000 "$BUILD_DIR/CMakeFiles/CMakeConfigureLog.yaml" > "$GAME_LOG_DIR/CMakeConfigureLog.yaml"
if [ -f "$GAME_LOG_DIR/build.log" ]; then
	grep -E "^FAILED:" "$GAME_LOG_DIR/build.log" | sort -u > "$GAME_LOG_DIR/failed-targets.txt"
	# every distinct error, with the file it came from
	grep -E "(error|fatal error):|undefined symbol" "$GAME_LOG_DIR/build.log" | sort | uniq -c | sort -rn > "$GAME_LOG_DIR/errors-unique.txt"
	grep -n -B2 -A10 -E "(error|fatal error):|undefined symbol" "$GAME_LOG_DIR/build.log" | head -c 1500000 > "$GAME_LOG_DIR/errors-context.txt"
	# keep the full log only if small enough for git
	if [ "$(stat -c %s "$GAME_LOG_DIR/build.log")" -gt 20000000 ]; then
		tail -c 20000000 "$GAME_LOG_DIR/build.log" > "$GAME_LOG_DIR/build.tail.log"
		rm "$GAME_LOG_DIR/build.log"
	fi
fi
command -v ccache >/dev/null && ccache -s > "$GAME_LOG_DIR/ccache.txt"
ls -la "$BUILD_DIR"/wesnoth* > "$GAME_LOG_DIR/outputs.txt" 2>&1 || true

echo "game build exit status: $STATUS" | tee "$GAME_LOG_DIR/status.txt"
exit "$STATUS"
