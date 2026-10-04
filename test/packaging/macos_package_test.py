"""Runs the real packaging script against controlled OS command boundaries."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/build_macos_dmg.sh'
class MacPackageContract(unittest.TestCase):
    def run_package(self, architectures, broken_signature=False, dependency_architectures=None):
        with tempfile.TemporaryDirectory(prefix='qpb-packaging-') as tmp:
            root=Path(tmp); app=root/'build/macos/Build/Products/Release/quadrant_planner.app'
            (app/'Contents/MacOS').mkdir(parents=True)
            (app/'Contents/MacOS/quadrant_planner').write_text('fixture binary')
            if dependency_architectures is not None:
                framework=app/'Contents/Frameworks/Fixture.framework'
                framework.mkdir(parents=True)
                (framework/'Fixture').write_text('fixture framework binary')
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'quadrant_planner','CFBundleShortVersionString':'1.0.0','CFBundleVersion':'9'}))
            bin_dir=root/'bin'; bin_dir.mkdir()
            commands={
                'file':'''case "$2" in */MacOS/*|*.framework/Fixture) echo 'Mach-O executable';; *) echo 'XML document';; esac''',
                'lipo':f'''case "$2" in *.framework/Fixture) echo "{dependency_architectures or architectures}";; *) echo "{architectures}";; esac''',
                'codesign':'exit 1' if broken_signature else 'exit 0', 'hdiutil':'''if [ "$1" = "create" ]; then for arg in "$@"; do case "$arg" in *.dmg) touch "$arg";; esac; done; fi
exit 0'''}
            for name,body in commands.items():
                path=bin_dir/name;path.write_text('#!/bin/sh\n'+body+'\n');path.chmod(0o755)
            env={k:v for k,v in os.environ.items() if not k.startswith('APPLE_')}
            env.update(PATH=str(bin_dir)+os.pathsep+env['PATH'],RUNNER_TEMP=str(root/'scratch'))
            (root/'scratch').mkdir()
            result=subprocess.run(['bash',str(SCRIPT)],cwd=root,env=env,capture_output=True,text=True)
            metadata=root/'dist/macos/metadata.json'
            return result.returncode, metadata.exists() and json.loads(metadata.read_text()), sorted(p.name for p in (root/'dist/macos').glob('*.dmg'))
    def test_actual_architecture_and_explicit_notarization_label(self):
        for arches,label in [('arm64','arm64'),('x86_64','x86_64'),('x86_64 arm64','universal')]:
            with self.subTest(arches=arches):
                code,meta,files=self.run_package(arches)
                self.assertEqual(code,0)
                self.assertEqual(files,[f'QuadrantPlanner-1.0.0-macos-{label}-not-notarized.dmg'])
                self.assertEqual(meta['architecture'],label)
                self.assertEqual(meta['signing'],'ad-hoc')
                self.assertFalse(meta['notarized'])
    def test_signing_failure_aborts_instead_of_publishing_invalid_app(self):
        code,_,files=self.run_package('arm64',broken_signature=True)
        self.assertNotEqual(code,0)
        self.assertEqual(files,[])
    def test_unknown_architecture_is_rejected(self):
        code,_,files=self.run_package('armv7')
        self.assertNotEqual(code,0)
        self.assertEqual(files,[])
    def test_universal_runner_with_thin_framework_cannot_publish_universal_dmg(self):
        code,meta,files=self.run_package('arm64 x86_64',dependency_architectures='arm64')
        self.assertNotEqual(code,0)
        self.assertFalse(meta)
        self.assertEqual(files,[])
        code,meta,files=self.run_package('arm64 x86_64',dependency_architectures='x86_64 arm64')
        self.assertEqual(code,0)
        self.assertEqual(meta['architecture'],'universal')
        self.assertEqual(len(files),1)
if __name__=='__main__':unittest.main()
