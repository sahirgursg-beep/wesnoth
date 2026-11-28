# Wesnoth in the browser (WebAssembly port)

This branch (`web`, based on upstream `1.20`) ports The Battle for Wesnoth to
WebAssembly with Emscripten, so the game runs in a web browser.

## Roadmap

1. **Browser build**: compile the game client to WebAssembly and get it running.
2. **Single-player release**: mainline campaigns and scenarios, no network play.
3. **Own content**: new factions, units and campaigns based on Anatolian and
   Asian mythology (as add-ons).
4. **Multiplayer**: WebSocket transport, testing and release.
5. Use what we learn here for a separate real-time strategy project.

## Technical approach

| Topic | Decision |
|---|---|
| Base | upstream `1.20` branch (SDL3) |
| Toolchain | Emscripten (emsdk), CMake, vcpkg with the `wasm32-emscripten-wesnoth` triplet in `web/vcpkg/triplets` |
| Exceptions | native wasm exceptions (`-fwasm-exceptions`), wasm setjmp/longjmp |
| Threads | none; places that use `std::thread`/`std::async` (loading screen, spritesheet generator) get a single-threaded path |
| Blocking main loop | JSPI (Asyncify as fallback for browsers without JSPI) |
| Saves and preferences | IDBFS (IndexedDB) |
| Game data | `core` package (config, UI, fonts, Turkish translation, each campaign's `_main.cfg`) before start; terrain, units, portraits, story art and sounds download in the background; each campaign's scenarios and art (`campaign-<dir>`) download when it is started. The game waits in `game_config_manager::load_game_config_for_game` |
| Network | disabled for the single-player release |

## CI

`.github/workflows/web.yml` runs on every push to `web`.

* `deps` (the only job) first builds all dependencies listed in `web/vcpkg/packages.txt` with
  `--keep-going`, so one run shows every failing port. Built ports are kept in
  the Actions cache.
* Logs of every run are pushed to the **`ci-logs`** branch
  (`runs/<run-number>-<job>/`, newest path in `LATEST-<job>`). Read them with:

  ```sh
  git fetch --depth 1 origin ci-logs && git show origin/ci-logs:LATEST-deps
  ```

* `web/ci/game.sh` then compiles the game with `ninja -k 0` (all errors in one
  run; logs under `runs/<n>-game/`, see `errors-unique.txt`). ccache keeps
  successful objects between runs.

Port fixes go in `web/vcpkg/ports/<port>` (vcpkg overlay ports):

| Port | Why |
|---|---|
| `vcpkg-tool-meson` | never add `-pthread` with emcc, so all libraries are single threaded |
| `glib` | `res_query()` stub, `size_t` detection with emcc, no `pthread_*_np`, no tools; exact function pointer signatures (from kleisauke's wasm-vips GLib) |
| `pango` | no tools; exact function pointer signatures (interface inits, `g_list_foreach`); fontconfig work runs inline instead of on a worker thread |
| `boost-locale` | CMake `source_group` error |

## Status

Preview: https://sahirgursg-beep.github.io/wesnoth/ (Chrome/Edge with JSPI)


- [x] dependencies build for wasm32
- [x] game client compiles
- [x] published on GitHub Pages
- [x] game starts and shows the main menu
- [x] a campaign scenario loads and responds to input (A Tale of Two Brothers)
- [x] canvas follows the browser window size (SDL fill-document mode)
- [x] Turkish translation (default language; `?lang=en` for English)
- [x] faster start: only the core package before the title screen
- [x] all single player campaigns (music not yet)
- [ ] music
- [ ] browsers without JSPI (Asyncify build)
- [x] saves persist across reloads (IDBFS); preferences are written when the tab is hidden or closed
