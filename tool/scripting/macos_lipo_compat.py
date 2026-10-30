#!/usr/bin/env python3
"""Opt-in build wrapper for the local macOS lipo multi-arch verification bug.

Usage: python3 tool/scripting/macos_lipo_compat.py run fvm flutter build macos --release

Only Flutter's ``lipo binary -verify_arch arch1 arch2 ...`` form is expanded
into real, individual architecture checks. Every requested slice must pass;
other lipo operations, tool output and exit statuses are preserved. The real
executable is resolved before a temporary PATH proxy is installed, preventing
recursive lookup. No SDK, project configuration or system executable is edited.
"""

import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def run_lipo(real_lipo, arguments):
    """Verify each requested slice or forward the original command unchanged."""
    if (
        len(arguments) >= 4
        and not arguments[0].startswith('-')
        and arguments[1] == '-verify_arch'
        and all(not arg.startswith('-') for arg in arguments[2:])
    ):
        for architecture in arguments[2:]:
            result = subprocess.run(
                [real_lipo, arguments[0], '-verify_arch', architecture],
                check=False,
            )
            if result.returncode != 0:
                return result.returncode
        return 0
    return subprocess.run([real_lipo, *arguments], check=False).returncode


def run_with_proxy(command):
    """Scope the compatible tool lookup to one command and clean up afterward."""
    # /usr/bin/lipo is an Xcode dispatcher, not the physical executable.
    # Resolve the tool before setting Xcode's search path to avoid recursion.
    real_lipo = subprocess.check_output(
        ['/usr/bin/xcrun', '--find', 'lipo'], text=True,
    ).strip()
    real_lipo = str(Path(real_lipo).resolve())
    with tempfile.TemporaryDirectory(prefix='getman-lipo-compat-') as directory:
        proxy = Path(directory) / 'lipo'
        invocation = shlex.join([
            sys.executable, str(Path(__file__).resolve()), 'lipo', real_lipo,
        ])
        proxy.write_text('#!/bin/sh\nexec ' + invocation + ' "$@"\n')
        proxy.chmod(0o700)
        environment = os.environ.copy()
        environment['PATH'] = directory + os.pathsep + environment.get('PATH', '')
        # Swift Build puts this search-path list before its own toolchain in
        # shell phases; PATH alone is appended after the toolchain and loses.
        # Preserve existing entries and scope this override to this subprocess.
        # Source: Core.createExecutableSearchPaths in
        # github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/Settings/Settings.swift
        search_paths = environment.get('__XCODE_BUILT_PRODUCTS_DIR_PATHS', '')
        environment['__XCODE_BUILT_PRODUCTS_DIR_PATHS'] = directory + (
            os.pathsep + search_paths if search_paths else ''
        )
        return subprocess.run(command, env=environment, check=False).returncode


def main(arguments):
    """Keep proxy mode separate from the explicitly opted-in build command."""
    if len(arguments) >= 3 and arguments[0] == 'lipo':
        return run_lipo(arguments[1], arguments[2:])
    if len(arguments) >= 2 and arguments[0] == 'run':
        return run_with_proxy(arguments[1:])
    sys.stderr.write(__doc__ + '\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
