import pathlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AssemblyTest(unittest.TestCase):
    def test_case_distinct_resources_are_preserved(self):
        with tempfile.TemporaryDirectory(prefix='turbo-apk-test-') as temporary:
            root = pathlib.Path(temporary)
            source, assembled, addon, output = [root / x for x in ('source.apk','assembled.apk','addon.dex','output.apk')]
            files = {'classes.dex': b'dex\noriginal1', 'classes2.dex': b'dex\noriginal2',
                     'classes3.dex': b'dex\noriginal3', 'res/A.xml': b'UPPER',
                     'res/a.xml': b'lower', 'AndroidManifest.xml': b'manifest',
                     'resources.arsc': b'arsc', 'lib/arm64-v8a/libflutter.so': b'native',
                     'META-INF/VENDOR.SF': b'old signature', 'META-INF/services/keep': b'keep'}
            with zipfile.ZipFile(source, 'w') as archive:
                for name, data in files.items(): archive.writestr(name, data)
            with zipfile.ZipFile(assembled, 'w') as archive: archive.writestr('classes2.dex', b'dex\npatched')
            addon.write_bytes(b'dex\naddon')
            subprocess.run(['python3',str(ROOT/'assemble_apk.py'),str(source),str(assembled),str(addon),str(output)],check=True,capture_output=True)
            with zipfile.ZipFile(output) as archive:
                for name, data in files.items():
                    if name in ('classes2.dex', 'META-INF/VENDOR.SF'): continue
                    self.assertEqual(archive.read(name), data)
                self.assertEqual(archive.read('classes2.dex'), b'dex\npatched')
                self.assertEqual(archive.read('classes4.dex'), b'dex\naddon')
                self.assertNotIn('META-INF/VENDOR.SF',archive.namelist())
            subprocess.run(['python3',str(ROOT/'verify_apk.py'),str(source),str(output)],check=True,capture_output=True)
            failure = subprocess.run(['python3',str(ROOT/'assemble_apk.py'),str(source),str(assembled),str(addon),str(source)],capture_output=True)
            self.assertNotEqual(failure.returncode,0)

if __name__ == '__main__': unittest.main()
