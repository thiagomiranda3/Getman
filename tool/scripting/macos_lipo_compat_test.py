"""Real Mach-O regressions for the opt-in lipo verification adapter.

Run with python3 tool/scripting/macos_lipo_compat_test.py on macOS. Fixtures
compile two tiny object files; no Flutter build, SDK mutation or network access.
"""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).with_name('macos_lipo_compat.py')
SPEC = importlib.util.spec_from_file_location('macos_lipo_compat', SCRIPT)
COMPAT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPAT)


class LipoCompatibilityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='getman-lipo-test-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        cls.real_lipo = shutil.which('lipo')
        source = cls.root / 'fixture.c'
        source.write_text('int getman_fixture(void) { return 42; }\n')
        for arch in ('arm64', 'x86_64'):
            subprocess.run(
                ['xcrun', 'clang', '-arch', arch, '-c', str(source),
                 '-o', str(cls.root / f'{arch}.o')], check=True,
            )
        cls.fat = cls.root / 'both architectures.o'
        subprocess.run(
            [cls.real_lipo, '-create', str(cls.root / 'arm64.o'),
             str(cls.root / 'x86_64.o'), '-output', str(cls.fat)], check=True,
        )

    def test_both_present_architectures_succeed(self):
        self.assertEqual(COMPAT.run_lipo(
            self.real_lipo, [str(self.fat), '-verify_arch', 'arm64', 'x86_64'],
        ), 0)

    def test_missing_second_architecture_still_fails(self):
        self.assertNotEqual(COMPAT.run_lipo(
            self.real_lipo,
            [str(self.root / 'arm64.o'), '-verify_arch', 'arm64', 'x86_64'],
        ), 0)

    def test_missing_first_architecture_still_fails(self):
        self.assertNotEqual(COMPAT.run_lipo(
            self.real_lipo,
            [str(self.root / 'arm64.o'), '-verify_arch', 'x86_64', 'arm64'],
        ), 0)

    def test_other_lipo_operations_keep_output_and_status(self):
        for arguments in (
            ['-info', str(self.fat)],
            [str(self.root / 'absent.o'), '-info'],
            [str(self.fat), '-verify_arch', 'unknown_arch'],
        ):
            with self.subTest(arguments=arguments):
                expected = subprocess.run(
                    [self.real_lipo, *arguments], capture_output=True,
                )
                actual = subprocess.run(
                    [sys.executable, str(SCRIPT), 'lipo', self.real_lipo,
                     *arguments], capture_output=True,
                )
                self.assertEqual(actual.returncode, expected.returncode)
                self.assertEqual(actual.stdout, expected.stdout)
                self.assertEqual(actual.stderr, expected.stderr)

    def test_build_command_uses_temporary_proxy_and_preserves_exit_status(self):
        evidence = self.root / 'proxy path.txt'
        child = (
            'import pathlib, shutil, subprocess, sys; '
            'proxy = shutil.which("lipo"); '
            'pathlib.Path(sys.argv[1]).write_text(proxy); '
            'result = subprocess.run([proxy, sys.argv[2], "-verify_arch", '
            '"arm64", "x86_64"]); '
            'sys.exit(23 if result.returncode == 0 else 24)'
        )
        result = subprocess.run(
            [sys.executable, str(SCRIPT), 'run', sys.executable, '-c', child,
             str(evidence), str(self.fat)], capture_output=True,
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        proxy = Path(evidence.read_text())
        self.assertNotEqual(str(proxy), self.real_lipo)
        self.assertFalse(proxy.exists(), 'Temporary proxy must be cleaned up')


if __name__ == '__main__':
    if sys.platform != 'darwin':
        sys.exit('These real Mach-O tests require macOS with lipo and clang.')
    unittest.main()
