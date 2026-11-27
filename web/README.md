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
| Game data | packaged separately and loaded on demand; size reduction is a later step |
| Network | disabled for the single-player release |

## CI

`.github/workflows/web.yml` runs on every push to `web`.

* `deps` builds all dependencies listed in `web/vcpkg/packages.txt` with
  `--keep-going`, so one run shows every failing port. Built ports are kept in
  the Actions cache.
* Logs of every run are pushed to the **`ci-logs`** branch
  (`runs/<run-number>-<job>/`, newest path in `LATEST-<job>`). Read them with:

  ```sh
  git fetch --depth 1 origin ci-logs && git show origin/ci-logs:LATEST-deps
  ```

Port fixes go in `web/vcpkg/ports/<port>` (vcpkg overlay ports).

## Status

- [ ] dependencies build for wasm32
- [ ] game client compiles
- [ ] game starts and shows the main menu
- [ ] tutorial is playable
- [ ] saves persist across reloads
- [ ] published on GitHub Pages
