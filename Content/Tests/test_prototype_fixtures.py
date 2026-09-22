import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'Content/Tools/make_prototype_fixtures.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class FixtureTests(unittest.TestCase):
    def test_pinned_integrity_and_semantics(self):
        manifest = json.loads((ROOT / 'Content/Source/prototype-manifest.json').read_text())
        payload = (ROOT / 'BibleReader/Resources/PrototypeChapters.json').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), manifest['fixtureSHA256'])
        chapters = json.loads(payload)
        self.assertEqual([len(c['verses']) for c in chapters], [25, 36, 54, 176])
        ids = [v['id'] for c in chapters for v in c['verses']]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(chapters[-1]['verses'][0]['headings'])
        self.assertTrue(chapters[-1]['verses'][0]['notes'])
        for chapter in chapters:
            for verse in chapter['verses']:
                text = ''.join(r['text'] for r in verse['runs'])
                self.assertEqual(text, text.strip())
                self.assertNotIn('\ufffd', text)
                self.assertNotIn('  ', text)

    def test_rejects_external_entities(self):
        with self.assertRaises(ValueError):
            fixtures.safe_xml(b'<!DOCTYPE a [<!ENTITY file SYSTEM "file:///etc/passwd">]><a>&file;</a>')


if __name__ == '__main__':
    unittest.main()
