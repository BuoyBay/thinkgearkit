#!/usr/bin/env python3
"""Build a declared native transport slice. No compiler/runtime installation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import tempfile

PACKAGE = Path(__file__).resolve().parent


def host_target():
    arch = {"AMD64": "x86_64", "aarch64": "arm64"}.get(platform.machine(), platform.machine())
    return arch + "-" + {"linux": "linux", "darwin": "darwin", "win32": "windows"}[sys.platform]


TRIPLES = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "arm64-linux": "aarch64-unknown-linux-gnu",
    "x86_64-windows": "x86_64-pc-windows-msvc",
    "arm64-windows": "aarch64-pc-windows-msvc",
    "x86_64-darwin": "x86_64-apple-macos",
    "arm64-darwin": "arm64-apple-macos",
}


def build(runtime_root=None, target=None, cc=None):
    target = target or host_target()
    system = target.split("-")[-1]
    filename = "buoy_thinkgearkit.dll" if system == "windows" else "libbuoy_thinkgearkit." + ("dylib" if system == "darwin" else "so")
    runtime_root = Path(runtime_root) if runtime_root is not None else PACKAGE / "runtime"
    output = runtime_root / TRIPLES[target] / filename
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler = shlex.split(cc or os.environ.get("CC", "cl" if sys.platform == "win32" else "cc"))
    sources = [PACKAGE / "native/bridge.c", PACKAGE / "native/discovery.c"]
    if system == "darwin":
        sources.append(PACKAGE / "native/macos.m")
        sources.append(PACKAGE / "native/ble.m")
        sources.append(PACKAGE / "native/discovery_macos.m")
    if Path(compiler[0]).stem in ("cl", "clang-cl"):
        link = runtime_root.parent / "link" / TRIPLES[target] / "buoy_thinkgearkit.lib"
        link.parent.mkdir(parents=True, exist_ok=True)
        command = compiler + ["/nologo", "/LD", "/O2", "/std:c11", "/D_CRT_SECURE_NO_WARNINGS"] + list(map(str, sources)) + [f"/Fe:{output}", "/link", "ws2_32.lib", "setupapi.lib", "advapi32.lib", "uuid.lib", f"/IMPLIB:{link}"]
    else:
        flags = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror"]
        if system == "darwin":
            flags += ["-fobjc-arc", "-fPIC", "-dynamiclib", "-arch", target.split("-")[0], "-mmacosx-version-min=11.0", "-framework", "Foundation", "-framework", "IOBluetooth", "-framework", "CoreBluetooth", "-framework", "CoreFoundation", "-Wl,-install_name,@rpath/" + filename]
        elif system == "windows":
            link = runtime_root.parent / "link" / TRIPLES[target] / "buoy_thinkgearkit.lib"
            link.parent.mkdir(parents=True, exist_ok=True)
            flags += ["-shared", "-Wl,--out-implib," + str(link)]
            if "mingw" in compiler[0] or "w64" in compiler[0]:
                flags += ["-static", "-static-libgcc"]
        else:
            flags += ["-fPIC", "-shared", "-Wl,-soname," + filename]
        command = compiler + flags + list(map(str, sources)) + ["-o", str(output)]
        if system == "windows":
            command += ["-lws2_32", "-lsetupapi", "-ladvapi32", "-luuid"]
    commands = []
    if system == "darwin":
        with tempfile.TemporaryDirectory(prefix="thinkgear-macos-") as temporary:
            objects = []
            for source in sources:
                obj = Path(temporary) / (source.stem + ".o")
                compile_flags = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-arch", target.split("-")[0], "-mmacosx-version-min=11.0"]
                if source.name in ("macos.m", "discovery_macos.m"):
                    compile_flags += ["-fobjc-arc"]
                if source.name == "ble.m":
                    compile_flags += ["-fno-objc-arc"]
                compile_command = compiler + compile_flags + ["-c", str(source), "-o", str(obj)]
                subprocess.run(compile_command, check=True)
                commands.append(compile_command)
                objects.append(obj)
            command = compiler + ["-dynamiclib", "-arch", target.split("-")[0], "-mmacosx-version-min=11.0", "-framework", "Foundation", "-framework", "IOBluetooth", "-framework", "CoreBluetooth", "-framework", "CoreFoundation", "-Wl,-install_name,@rpath/" + filename] + list(map(str, objects)) + ["-o", str(output)]
            subprocess.run(command, check=True)
            commands.append(command)
    else:
        subprocess.run(command, check=True)
        commands.append(command)
    receipt = {"target": target, "commands": commands, "native_execution": False, "sources": {str(p.relative_to(PACKAGE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    output.with_name(output.name + ".build.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(output)
    return target, output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TRIPLES)
    parser.add_argument("--cc")
    parser.add_argument("--runtime-root", type=Path)
    args = parser.parse_args()
    build(args.runtime_root, args.target, args.cc)
