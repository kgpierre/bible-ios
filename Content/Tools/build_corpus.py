"""Deterministic, offline conversion of the pinned eBible USFX edition."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import sqlite3
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / 'Content/Source/eng-kjv_usfx.zip'
PIN = '6d834ebe8bcf157587ce93b774615d9e9554f1201951a072cc379930d49bb6fb'
EDITION = 'eng-kjv-1769-protestant'
BOOKS = 'GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV'.split()
CONFIG = {'editionID': EDITION, 'includedBooks': BOOKS, 'canonReview': 'Proposed engineering configuration; owner confirmation required before release', 'importerVersion': 1, 'documentVersion': 1}


def digest(data): return hashlib.sha256(data).hexdigest()
def packed(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
def text(node): return ' '.join(''.join(node.itertext()).split())


def safe_xml(xml):
    if b'<!DOCTYPE' in xml.upper() or b'<!ENTITY' in xml.upper() or b'\x00' in xml:
        raise ValueError('DTD/entities and non-UTF8 XML forbidden')
    return ET.fromstring(xml)

class NoticeText(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts=[]; self.in_paragraph=False
    def handle_starttag(self,tag,attrs):
        if tag=='p': self.in_paragraph=True; self.parts.append('\n\n')
        if tag=='br' and self.in_paragraph: self.parts.append('\n')
    def handle_endtag(self,tag):
        if tag=='p': self.in_paragraph=False
    def handle_data(self,data):
        if self.in_paragraph: self.parts.append(data)

def read_source(path=ARCHIVE):
    data = path.read_bytes()
    if digest(data) != PIN: raise ValueError('Archive checksum differs from pinned source')
    with zipfile.ZipFile(path) as archive:
        names = set()
        total = 0
        for item in archive.infolist():
            p = PurePosixPath(item.filename)
            total += item.file_size
            if p.is_absolute() or '..' in p.parts or '\\' in item.filename or item.filename in names:
                raise ValueError('Unsafe or duplicate archive path')
            if item.file_size > 20_000_000 or total > 40_000_000 or p.suffix not in {'.xml', '.htm', '.asc', '.css'}:
                raise ValueError('Unexpected archive content/size')
            if (item.external_attr >> 16) & 0o170000 == 0o120000: raise ValueError('Archive symlink forbidden')
            names.add(item.filename)
        xml = archive.read('eng-kjv_usfx.xml')
        if b'<!DOCTYPE' in xml.upper() or b'<!ENTITY' in xml.upper() or b'\x00' in xml:
            raise ValueError('DTD/entities and non-UTF8 XML forbidden')
        return safe_xml(xml), archive.read('copr.htm')


def parse_book(book):
    code = book.attrib['id']
    name = text(book.find("toc[@level='2']"))
    title = text(book.find("toc[@level='1']"))
    chapters = []
    chapter = verse = None
    pending = []
    structure = 'p'
    allowed = {'book','id','h','toc','ide','p','c','v','ve','q','b','w','wj','add','nd','f','fr','ft','s','d','tl'}
    for node in book.iter():
        if node.tag not in allowed: raise ValueError(f'Unhandled marker {code}: {node.tag}')
    def finish():
        nonlocal chapter
        if chapter:
            chapter['trailingBlocks'] = list(pending)
            pending.clear()
            if not chapter['verses']: raise ValueError('Empty chapter')
            labels = [v['label'] for v in chapter['verses']]
            if labels != [str(i) for i in range(1,len(labels)+1)]:
                raise ValueError(f'Nonsequential/bridged labels need explicit handling: {chapter["id"]}')
            chapters.append(chapter)
    def append(value, italic):
        if not value: return
        if verse is None:
            if value.strip(): raise ValueError(f'Unanchored text in {code}: {value!r}')
            return
        for char in value:
            char = ' ' if char.isspace() else char
            runs = verse['runs']
            if char == ' ' and (not runs or runs[-1]['text'].endswith(' ')): continue
            if runs and runs[-1]['italic'] == italic: runs[-1]['text'] += char
            else: runs.append({'text': char, 'italic': italic})
    def visit(node, italic=False):
        nonlocal verse, structure
        tag = node.tag
        if tag == 'v':
            if verse is not None: raise ValueError('Nested verse')
            label = node.attrib['id']
            verse = {'id': f'{chapter["id"]}:{label}', 'label': label, 'runs': [], 'structure': structure,
                     'headings': [b['text'] for b in pending], 'notes': [], 'sourceBlocks': list(pending)}
            pending.clear()
            chapter['verses'].append(verse)
        elif tag == 've':
            if verse is None: raise ValueError('Unmatched verse end')
            if verse['runs']: verse['runs'][-1]['text'] = verse['runs'][-1]['text'].rstrip()
            verse['runs'] = [r for r in verse['runs'] if r['text']]
            if not verse['runs']: raise ValueError('Empty verse')
            verse = None
        elif tag == 'f':
            if verse is None: raise ValueError('Unanchored footnote')
            verse['notes'].append(text(node))
            return
        elif tag in {'s', 'd'}:
            pending.append({'kind': tag, 'text': text(node), 'sourceXML': ET.tostring(node, encoding='unicode')})
            return
        elif tag not in {'p','q','b','w','wj','add','nd','tl'}: raise ValueError(f'Unexpected content marker {tag}')
        if tag in {'p','q'}: structure = node.attrib.get('style',tag)
        italic = italic or tag == 'add'
        append(node.text, italic)
        for child in node:
            visit(child, italic)
            append(child.tail, italic)
    metadata = []
    for node in book:
        if node.tag == 'c':
            if verse is not None: raise ValueError('Unclosed verse at chapter boundary')
            finish()
            chapter = {'id': f'{EDITION}:{code}:{node.attrib["id"]}', 'bookID': code, 'bookName': name,
                       'eyebrow': 'THE GOSPEL ACCORDING TO' if code in {'MAT','MRK','LUK','JHN'} else 'THE BOOK OF',
                       'label': node.attrib['id'], 'editionLabel': 'KJV', 'verses': [], 'sourceTitle': title}
        elif chapter is None:
            metadata.append(ET.tostring(node, encoding='unicode'))
        else: visit(node)
    finish()
    return {'id':code,'name':name,'shortName':text(book.find("toc[@level='3']")), 'title':title, 'sourceMetadataXML':metadata}, chapters


def convert(output):
    root, notice = read_source()
    by_id = {b.attrib['id']: b for b in root.findall('book')}
    if len(by_id) != len(root.findall('book')): raise ValueError('Duplicate source books')
    documents, books = [], []
    for code in BOOKS:
        book, chapters = parse_book(by_id[code]); books.append(book); documents.extend(chapters)
    ids = [v['id'] for c in documents for v in c['verses']]
    if len(set(ids)) != len(ids): raise ValueError('Duplicate verse identities')
    for c in documents:
        for v in c['verses']:
            if '\ufffd' in ''.join(r['text'] for r in v['runs']): raise ValueError('Replacement character')
    logical = digest(packed({'books':books,'chapters':documents}).encode())
    counts = {c['id']:len(c['verses']) for c in documents}
    expected_path = ROOT / 'Content/Source/edition-counts.json'
    if expected_path.exists() and json.loads(expected_path.read_text()) != counts:
        raise ValueError('Counts changed from pinned edition inventory')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        dbpath = Path(temporary)/'BibleCorpus.sqlite'
        db = sqlite3.connect(dbpath)
        db.executescript('''
PRAGMA foreign_keys=ON;
PRAGMA user_version=1;
CREATE TABLE edition(id TEXT PRIMARY KEY,revision TEXT NOT NULL,documentVersion INTEGER NOT NULL);
CREATE TABLE book(id TEXT PRIMARY KEY,name TEXT NOT NULL,shortName TEXT NOT NULL,ordinal INTEGER UNIQUE NOT NULL,metadata TEXT NOT NULL);
CREATE TABLE chapter(id TEXT PRIMARY KEY,bookID TEXT NOT NULL REFERENCES book(id),label TEXT NOT NULL,ordinal INTEGER UNIQUE NOT NULL,UNIQUE(bookID,label));
CREATE TABLE chapter_document(chapterID TEXT PRIMARY KEY REFERENCES chapter(id),payload TEXT NOT NULL);
CREATE TABLE verse(id TEXT PRIMARY KEY,chapterID TEXT NOT NULL REFERENCES chapter(id),label TEXT NOT NULL,ordinal INTEGER UNIQUE NOT NULL,text TEXT NOT NULL,UNIQUE(chapterID,label));
CREATE INDEX verse_chapter ON verse(chapterID);
CREATE TABLE reference_alias(alias TEXT NOT NULL,bookID TEXT NOT NULL REFERENCES book(id),PRIMARY KEY(alias,bookID));
CREATE VIRTUAL TABLE verse_search USING fts5(verseID UNINDEXED,text,tokenize='unicode61');
''')
        db.execute('INSERT INTO edition VALUES(?,?,1)',(EDITION,logical))
        for i,b in enumerate(books):
            db.execute('INSERT INTO book VALUES(?,?,?,?,?)',(b['id'],b['name'],b['shortName'],i,packed(b)))
            for alias in sorted({b['id'].lower(),b['name'].lower(),b['shortName'].lower()}):
                db.execute('INSERT INTO reference_alias VALUES(?,?)',(alias,b['id']))
        ordinal=0
        for i,c in enumerate(documents):
            db.execute('INSERT INTO chapter VALUES(?,?,?,?)',(c['id'],c['bookID'],c['label'],i))
            db.execute('INSERT INTO chapter_document VALUES(?,?)',(c['id'],packed(c)))
            for v in c['verses']:
                wording=''.join(r['text'] for r in v['runs'])
                db.execute('INSERT INTO verse VALUES(?,?,?,?,?)',(v['id'],c['id'],v['label'],ordinal,wording))
                db.execute('INSERT INTO verse_search VALUES(?,?)',(v['id'],wording));ordinal+=1
        db.commit()
        if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok' or db.execute('PRAGMA foreign_key_check').fetchall():
            raise ValueError('Corpus integrity failure')
        db.close()
        binary=digest(dbpath.read_bytes())
        dbpath.replace(output/'BibleCorpus.sqlite')
    manifest={**CONFIG,'contentRevision':logical,'schemaVersion':1,'providerID':'eng-kjv', 'versificationID':'eng-kjv-1769-source-labels', 'language':'en',
              'sourcePage':'https://ebible.org/find/show.php?id=eng-kjv','sourceURL':'https://ebible.org/Scriptures/eng-kjv_usfx.zip',
              'retrieved':'2026-09-21','sourceDateInArchiveNotice':'2026-09-17','archiveSHA256':PIN,'outputSHA256':binary,
              'configurationSHA256':digest(packed(CONFIG).encode()),'importerSHA256':digest(Path(__file__).read_bytes()),
              'excludedBooks':[x for x in by_id if x not in BOOKS], 'bookCount':len(books),'chapterCount':len(documents),'verseCount':len(ids),
              'rightsReview':'Unresolved; do not publish until edition, canon, and territories are reviewed',
              'normalization':'Collapse XML formatting whitespace only; retain add italics, source headings, notes and structural metadata; lexical IDs remain in pinned raw source.',
              'attribution':'King James Version (standardized 1769 source), provided by CrossWire Bible Society and eBible.org. Original source includes Apocrypha; this configured corpus includes 66 books.'}
    (output/'CorpusManifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    notice_parser=NoticeText();notice_parser.feed(notice.decode('utf-8-sig'))
    provider_notice=''.join(notice_parser.parts).strip()
    (output/'EditionNotice.txt').write_text('King James Version\n\n'+manifest['attribution']+'\n\n'+manifest['rightsReview']+'\n\nSource: '+manifest['sourcePage']+'\n\nOriginal provider notice:\n'+provider_notice+'\n')
    (ROOT/'Content/Source/edition-counts.json').write_text(json.dumps(counts,indent=2)+'\n')
    (ROOT/'Content/Source/copr.htm').write_bytes(notice)
    print(f'{len(books)} books, {len(documents)} chapters, {len(ids)} verses; logical SHA-256 {logical}')
    return documents, manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'BibleReader/Resources')
    convert(parser.parse_args().output)
