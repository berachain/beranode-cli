#!/usr/bin/env python3
"""Zig CGO wrapper for cross-compiling Go to darwin-arm64.

Go's external linker (when CGO_ENABLED=1) passes host/clang flags that Zig
does not treat as a macOS sysroot lookup:

  -arch arm64                         Apple clang; not a Zig flag
  -Wl,--compress-debug-sections=zlib  GNU ld; invalid for Mach-O
  -lresolv                            Darwin lib, re-exported by libSystem;
                                      Zig reports "searched paths: none"
                                      under the paths_first strategy

This wrapper strips those flags and invokes zig cc/c++ with
-target aarch64-macos so Zig uses its bundled macOS libc and TBD stubs.
"""
from __future__ import annotations

import os
import sys


def zig_path() -> str:
    env = os.environ.get("ZIG_PATH")
    if env:
        return env
    path_file = "/usr/local/etc/zig-path"
    if os.path.isfile(path_file):
        with open(path_file, encoding="utf-8") as fh:
            return fh.read().strip()
    return "zig"


ZIG = zig_path()
TARGET = os.environ.get("ZIG_TARGET", "aarch64-macos")
MODE = "c++" if os.path.basename(sys.argv[0]) == "zigcxx" else "cc"

SKIP_EXACT = {
    "-lresolv",
    "-Wl,--compress-debug-sections=zlib",
}

args: list[str] = []
it = iter(sys.argv[1:])
for arg in it:
    if arg == "-arch":
        next(it, None)
        continue
    if arg == "-framework":
        next(it, None)
        continue
    if arg in SKIP_EXACT or arg.startswith("-Wl,--compress-debug-sections"):
        continue
    args.append(arg)

# Frameworks (CoreFoundation, Security, ...) are not in Zig's sysroot.
# They exist on every Mac at runtime; allow the linker to leave them unbound.
os.execv(
    ZIG,
    [ZIG, MODE, "-target", TARGET, "-Wl,-undefined,dynamic_lookup", *args],
)
