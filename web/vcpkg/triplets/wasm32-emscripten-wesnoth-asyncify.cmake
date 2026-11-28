# vcpkg triplet for the Asyncify (no JSPI) Wesnoth browser build.
#
# Based on vcpkg's community "wasm32-emscripten" triplet, with:
#   * JavaScript-based exceptions (-fexceptions): Asyncify cannot handle native
#     wasm exceptions. Used by the Asyncify build for browsers without JSPI
#     (Safari, every iOS browser). Wesnoth relies heavily
#     on C++ exceptions, and every static library must use the same model
#   * Emscripten setjmp/longjmp (libpng, libjpeg and Lua use it)
#   * no pthreads (the game is linked with JSPI/Asyncify and runs single threaded)
#   * release-only builds to halve CI time

set(VCPKG_ENV_PASSTHROUGH_UNTRACKED EMSCRIPTEN_ROOT EMSDK PATH)

if(NOT DEFINED ENV{EMSCRIPTEN_ROOT})
   find_path(EMSCRIPTEN_ROOT "emcc")
else()
   set(EMSCRIPTEN_ROOT "$ENV{EMSCRIPTEN_ROOT}")
endif()

if(NOT EMSCRIPTEN_ROOT)
   if(NOT DEFINED ENV{EMSDK})
      message(FATAL_ERROR "The emcc compiler not found in PATH")
   endif()
   set(EMSCRIPTEN_ROOT "$ENV{EMSDK}/upstream/emscripten")
endif()

if(NOT EXISTS "${EMSCRIPTEN_ROOT}/cmake/Modules/Platform/Emscripten.cmake")
   message(FATAL_ERROR "Emscripten.cmake toolchain file not found")
endif()

set(VCPKG_TARGET_ARCHITECTURE wasm32)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Emscripten)
set(VCPKG_BUILD_TYPE release)

# The wrapper toolchain includes Emscripten.cmake and then applies the flags below.
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${VCPKG_ROOT_DIR}/scripts/toolchains/emscripten.cmake")

# C code gets no -fexceptions: it needs no landing pads, and with them
# C-only programs (e.g. cairo's csi tools) fail to link (__resumeException).
set(VCPKG_C_FLAGS "-sSUPPORT_LONGJMP=emscripten")
set(VCPKG_CXX_FLAGS "-fexceptions -sSUPPORT_LONGJMP=emscripten")
# C programs that link C++ static libraries (pango's utils use harfbuzz) need
# the C++ runtime and JS exception helpers: -sDEFAULT_TO_CXX links them even
# when the driver is emcc.
set(VCPKG_LINKER_FLAGS "-fexceptions -sSUPPORT_LONGJMP=emscripten -sDEFAULT_TO_CXX")
