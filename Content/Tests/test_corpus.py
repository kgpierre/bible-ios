import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_corpus',ROOT/'Content/Tools/build_corpus.py')
corpus = importlib.util.module_from_spec(spec);spec.loader.exec_module(corpus)

class CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db=sqlite3.connect(f'file:{ROOT}/BibleReader/Resources/BibleCorpus.sqlite?mode=ro',uri=True)
        cls.source,_=corpus.read_source()

    @classmethod
    def tearDownClass(cls): cls.db.close()

    def test_inventory_and_integrity(self):
        manifest=json.loads((ROOT/'BibleReader/Resources/CorpusManifest.json').read_text())
        self.assertEqual(manifest['includedBooks'],corpus.BOOKS)
        self.assertEqual([r[0] for r in self.db.execute('SELECT id FROM book ORDER BY ordinal')],corpus.BOOKS)
        self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchone(),('ok',))
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(),[])
        self.assertEqual(self.db.execute('SELECT count(*) FROM verse').fetchone()[0],manifest['verseCount'])
        inventory=json.loads((ROOT/'Content/Source/edition-counts.json').read_text())
        self.assertEqual(dict(self.db.execute('SELECT chapterID,count(*) FROM verse GROUP BY chapterID')),inventory)
        self.assertEqual(hashlib.sha256((ROOT/'BibleReader/Resources/BibleCorpus.sqlite').read_bytes()).hexdigest(),manifest['outputSHA256'])
        self.assertIn('TOB',manifest['excludedBooks'])

    def test_every_verse_matches_independent_source_extraction(self):
        # Independent event walker: no importer run builder, ignores typed notes/headings.
        expected={}
        for book in self.source.findall('book'):
            code=book.attrib['id']
            if code not in corpus.BOOKS: continue
            chapter=None; verse=None; fragments=[]
            def visit(node):
                nonlocal chapter,verse,fragments
                if node.tag in {'f','s','d','id','h','toc','ide'}: return
                if node.tag=='c': chapter=node.attrib['id']
                if node.tag=='v': verse=node.attrib['id'];fragments=[]
                if node.tag=='ve':
                    expected[f'{corpus.EDITION}:{code}:{chapter}:{verse}']=' '.join(''.join(fragments).split())
                    verse=None
                if verse and node.text: fragments.append(node.text)
                for child in node:
                    visit(child)
                    if verse and child.tail: fragments.append(child.tail)
            visit(book)
        self.assertEqual(dict(self.db.execute('SELECT id,text FROM verse')),expected)

    def test_golden_chapters_and_previous_fixtures(self):
        fixtures=json.loads((ROOT/'BibleReader/Resources/PrototypeChapters.json').read_text())
        for fixture in fixtures:
            chapter=f'{corpus.EDITION}:{fixture["bookID"]}:{fixture["label"]}'
            document=json.loads(self.db.execute('SELECT payload FROM chapter_document WHERE chapterID=?',(chapter,)).fetchone()[0])
            for old,new in zip(fixture['verses'],document['verses'],strict=True):
                for key in ['label','runs','headings','notes']: self.assertEqual(old[key],new[key])
        for book,chapter in [('GEN','1'),('PSA','23'),('PSA','119'),('JHN','3'),('JUD','1'),('REV','22')]:
            doc=json.loads(self.db.execute('SELECT payload FROM chapter_document WHERE chapterID=?',(f'{corpus.EDITION}:{book}:{chapter}',)).fetchone()[0])
            for verse in doc['verses']:
                wording=self.db.execute('SELECT text FROM verse WHERE id=?',(verse['id'],)).fetchone()[0]
                self.assertEqual(wording,''.join(r['text'] for r in verse['runs']))
            if (book,chapter)==('PSA','23'): self.assertTrue(doc['verses'][0]['sourceBlocks'])

    def test_search_first_last_and_negative(self):
        for term,verse in [('"In the beginning"',f'{corpus.EDITION}:GEN:1:1'),('"grace of our Lord"',f'{corpus.EDITION}:REV:22:21')]:
            found={r[0] for r in self.db.execute('SELECT verseID FROM verse_search WHERE verse_search MATCH ?',(term,))}
            self.assertIn(verse,found)
        self.assertEqual(self.db.execute('SELECT count(*) FROM verse_search WHERE verse_search MATCH ?',('zxqvnonexistent',)).fetchone()[0],0)

    def test_unhandled_marker_and_entity_rejected(self):
        for xml in [b'<!DOCTYPE x><x/>',b'<!ENTITY x SYSTEM "file:///private"><x/>',b'\x00<x/>']:
            with self.assertRaises(ValueError): corpus.safe_xml(xml)
        book=ET.fromstring(ET.tostring(self.source.find("book[@id='GEN']")))
        ET.SubElement(book,'unexpected')
        with self.assertRaises(ValueError): corpus.parse_book(book)

    def test_reproducible_logical_and_binary_output(self):
        with tempfile.TemporaryDirectory() as directory:
            _,manifest=corpus.convert(Path(directory))
            shipped=json.loads((ROOT/'BibleReader/Resources/CorpusManifest.json').read_text())
            self.assertEqual(manifest['contentRevision'],shipped['contentRevision'])
            self.assertEqual(manifest['outputSHA256'],shipped['outputSHA256'])

if __name__=='__main__': unittest.main()
