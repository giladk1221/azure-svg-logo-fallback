import base64, importlib.util, json, pathlib, subprocess, tempfile, unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('publisher',ROOT/'scripts/publish.py')
publisher=importlib.util.module_from_spec(spec);spec.loader.exec_module(publisher)
class DeliveryTests(unittest.TestCase):
    def test_reproducible_package_and_clean_contents(self):
        import hashlib,zipfile
        subprocess.run(['python3','scripts/package.py'],cwd=ROOT,check=True,capture_output=True)
        one=(ROOT/'.build/function.zip').read_bytes()
        subprocess.run(['python3','scripts/package.py'],cwd=ROOT,check=True,capture_output=True)
        self.assertEqual(one,(ROOT/'.build/function.zip').read_bytes())
        with zipfile.ZipFile(ROOT/'.build/function.zip') as z:
            self.assertIn('host.json',z.namelist())
            self.assertIn('LogoRouter/function.json',z.namelist())
            self.assertFalse(any('local.settings' in n or n.endswith('.tfstate') for n in z.namelist()))
    def test_publisher_refuses_public_storage_resolution(self):
        with patch.object(publisher.socket,'getaddrinfo',return_value=[(2,1,6,'',('20.0.0.1',443))]),patch.object(publisher,'token') as token:
            with self.assertRaisesRegex(RuntimeError,'private addresses'):
                publisher.upload('example','logos','X.svg',b'<svg/>','image/svg+xml',True)
            token.assert_not_called()
    def test_no_catalog_writes_unless_explicitly_seeded(self):
        payload={'host':'host','package_name':'hash.zip','package':base64.b64encode(b'zip').decode()}
        with patch.object(publisher,'upload') as upload:
            publisher.publish(payload,True)
            self.assertEqual(upload.call_count,1)
            self.assertEqual(upload.call_args.args[:3],('host','packages','hash.zip'))
    def test_no_overwrite_on_conflicting_existing_blob(self):
        import urllib.error,io
        class Response(io.BytesIO):
            def __enter__(self):return self
            def __exit__(self,*args):self.close()
        conflict=urllib.error.HTTPError('https://example',412,'exists',{},None)
        with patch.object(publisher.socket,'getaddrinfo',return_value=[(2,1,6,'',('10.0.0.5',443))]),patch.object(publisher,'token',return_value='fake'),patch.object(publisher.urllib.request,'urlopen',side_effect=[conflict,Response(b'different')]):
            with self.assertRaisesRegex(RuntimeError,'Refusing to overwrite'):
                publisher.upload('example','logos','X.svg',b'<svg/>','image/svg+xml',True)
if __name__=='__main__':unittest.main()
