"""Real Mach-O regressions for the opt-in lipo verification adapter.

Run with python3 tool/scripting/macos_lipo_compat_test.py on macOS. Fixtures
compile two tiny object files; no Flutter build, SDK mutation or network access.
"""

import importlib.util
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import signal
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

    def run_adapter(self, arguments, environment=None):
        # A tool lookup regression can recurse through Apple's dispatcher.
        # Bound the entire process group, including descendants, on failure.
        command = [sys.executable, str(SCRIPT), *arguments]
        process = subprocess.Popen(
            command, env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            self.fail('Adapter command timed out; terminated its process group')
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

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
        result = self.run_adapter(
            ['run', sys.executable, '-c', child, str(evidence), str(self.fat)],
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        proxy = Path(evidence.read_text())
        self.assertNotEqual(str(proxy), self.real_lipo)
        self.assertFalse(proxy.exists(), 'Temporary proxy must be cleaned up')


    def test_xcode_script_uses_proxy_and_preserves_existing_xcconfig(self):
        project = self.root / 'Probe.xcodeproj'
        project.mkdir()
        which = self.root / 'xcode-proxy.txt'
        inherited_setting = self.root / 'xcode-setting.txt'
        original_config = self.root / 'original settings.xcconfig'
        original_config.write_text('GETMAN_EXISTING_CONFIG = preserved\n')
        ids = [f'{index:024X}' for index in range(1, 8)]
        proj, target, phase, group, configs, config, target_configs = ids
        script = (
            'command -v lipo > ' + shlex.quote(str(which)) + '\n'
            'printf "%s" "$GETMAN_EXISTING_CONFIG" > '
            + shlex.quote(str(inherited_setting)) + '\n'
            'lipo ' + shlex.quote(str(self.fat))
            + ' -verify_arch arm64 x86_64\n'
        )
        objects = {
            proj: dict(
                isa='PBXProject', buildConfigurationList=configs,
                compatibilityVersion='Xcode 14.0', mainGroup=group,
                projectDirPath='', projectRoot='', targets=[target], attributes={},
            ),
            target: dict(
                isa='PBXAggregateTarget', buildConfigurationList=target_configs,
                buildPhases=[phase], dependencies=[], name='Probe',
                productName='Probe',
            ),
            phase: dict(
                isa='PBXShellScriptBuildPhase', buildActionMask=2147483647,
                files=[], inputPaths=[], outputPaths=[],
                runOnlyForDeploymentPostprocessing=0, shellPath='/bin/sh',
                shellScript=script,
            ),
            group: dict(isa='PBXGroup', children=[], sourceTree='<group>'),
            config: dict(isa='XCBuildConfiguration', buildSettings={}, name='Debug'),
        }
        for identifier in (configs, target_configs):
            objects[identifier] = dict(
                isa='XCConfigurationList', buildConfigurations=[config],
                defaultConfigurationIsVisible=0, defaultConfigurationName='Debug',
            )
        (project / 'project.pbxproj').write_bytes(plistlib.dumps(dict(
            archiveVersion='1', classes={}, objectVersion='56',
            objects=objects, rootObject=proj,
        )))
        environment = os.environ.copy()
        environment['XCODE_XCCONFIG_FILE'] = str(original_config)
        result = self.run_adapter([
            'run', 'xcodebuild', '-project', str(project), '-scheme', 'Probe',
            '-derivedDataPath', str(self.root / 'derived'), 'build',
        ], environment=environment)
        (self.root / 'xcode.log').write_text(result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout[-2500:])
        proxy = Path(which.read_text().strip())
        self.assertIn('getman-lipo-compat-', str(proxy))
        self.assertFalse(proxy.exists(), 'Proxy must be removed after Xcode exits')
        self.assertEqual(inherited_setting.read_text(), 'preserved')
        self.assertEqual(
            original_config.read_text(), 'GETMAN_EXISTING_CONFIG = preserved\n',
        )


if __name__ == '__main__':
    if sys.platform != 'darwin':
        sys.exit('These real Mach-O tests require macOS with lipo and clang.')
    unittest.main()
