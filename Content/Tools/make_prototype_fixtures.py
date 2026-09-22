"""Narrow, offline USFX fixture conversion. Not the production corpus importer."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / 'Content/Source/eng-kjv_usfx.zip'
SHA256 = '6d834ebe8bcf157587ce93b774615d9e9554f1201951a072cc379930d49bb6fb'
SELECTION = {'JHN': {'2': 25, '3': 36, '4': 54}, 'PSA': {'119': 176}}


def safe_xml(data):
    if b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('DTD/entities are forbidden')
    return ET.fromstring(data)


def convert():
    assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == SHA256
    with zipfile.ZipFile(ARCHIVE) as archive:
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and '..' not in path.parts
            assert item.file_size < 20_000_000
            assert path.suffix in {'.xml', '.htm', '.asc', '.css'}
        root = safe_xml(archive.read('eng-kjv_usfx.xml'))
        (ROOT / 'Content/Source/copr.htm').write_bytes(archive.read('copr.htm'))
    chapters = []
    for book in root.findall('book'):
        code = book.attrib['id']
        if code not in SELECTION:
            continue
        chapter = None
        verse = None
        paragraph = 'p'
        pending_headings = []

        def append(text, italic):
            if verse is None or not text:
                return
            # Collapse XML formatting whitespace without changing words/punctuation.
            for char in text:
                char = ' ' if char.isspace() else char
                runs = verse['runs']
                if char == ' ' and (not runs or runs[-1]['text'].endswith(' ')):
                    continue
                if runs and runs[-1]['italic'] == italic:
                    runs[-1]['text'] += char
                else:
                    runs.append({'text': char, 'italic': italic})

        def visit(node, italic=False):
            nonlocal verse, paragraph
            tag = node.tag
            if tag == 'v':
                verse = {'id': f'prototype-eng-kjv:{code}:{chapter["label"]}:{node.attrib["id"]}',
                         'label': node.attrib['id'], 'runs': [], 'structure': paragraph,
                         'headings': list(pending_headings), 'notes': []}
                pending_headings.clear()
                chapter['verses'].append(verse)
            elif tag == 've':
                if verse and verse['runs']:
                    verse['runs'][-1]['text'] = verse['runs'][-1]['text'].rstrip()
                    verse['runs'] = [r for r in verse['runs'] if r['text']]
                verse = None
            elif tag == 'f':
                if verse is not None:
                    verse['notes'].append(' '.join(''.join(node.itertext()).split()))
                return
            elif tag == 's':
                pending_headings.append(' '.join(''.join(node.itertext()).split()))
                return
            elif tag not in {'p', 'q', 'b', 'w', 'wj', 'add', 'nd'}:
                raise ValueError(f'Unhandled fixture marker {tag}')
            if tag in {'p', 'q'}:
                paragraph = node.attrib.get('style', tag)
            italic = italic or tag == 'add'
            append(node.text, italic)
            for child in node:
                visit(child, italic)
                append(child.tail, italic)

        for node in book:
            if node.tag == 'c':
                verse = None
                label = node.attrib['id']
                chapter = None
                pending_headings.clear()
                if label in SELECTION[code]:
                    chapter = {'id': f'prototype-eng-kjv:{code}:{label}', 'bookID': code,
                               'bookName': 'John' if code == 'JHN' else 'Psalms',
                               'eyebrow': 'THE GOSPEL ACCORDING TO' if code == 'JHN' else 'THE BOOK OF',
                               'label': label, 'editionLabel': 'KJV · development fixture', 'verses': []}
                    chapters.append(chapter)
            elif chapter is not None:
                visit(node)
        for result in [c for c in chapters if c['bookID'] == code]:
            expected = SELECTION[code][result['label']]
            assert [v['label'] for v in result['verses']] == [str(i) for i in range(1, expected + 1)]
            assert all(v['runs'] for v in result['verses'])
    chapters.sort(key=lambda c: (c['bookID'] != 'JHN', int(c['label'])))
    payload = json.dumps(chapters, ensure_ascii=False, indent=2) + '\n'
    out = ROOT / 'BibleReader/Resources/PrototypeChapters.json'
    out.write_text(payload)
    manifest = {'usage': 'Debug-only renderer fixtures; not a release corpus or canon decision',
                'sourceURL': 'https://ebible.org/Scriptures/eng-kjv_usfx.zip',
                'sourcePage': 'https://ebible.org/find/show.php?id=eng-kjv',
                'retrieved': '2026-09-21', 'archiveSHA256': SHA256,
                'providerID': 'eng-kjv', 'providerLabel': 'King James Version + Apocrypha',
                'rightsReview': 'Unresolved for release territories; see original copr.htm',
                'conversion': 'v1; XML whitespace collapsed; add retains italics; w/wj/nd retain wording; poetry, source headings and notes retained separately; lexical IDs not rendered',
                'chapters': {c['id']: len(c['verses']) for c in chapters},
                'fixtureSHA256': hashlib.sha256(payload.encode()).hexdigest()}
    (ROOT / 'Content/Source/prototype-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Pinned fixtures:', [(c['bookName'], c['label'], len(c['verses'])) for c in chapters])


if __name__ == '__main__':
    convert()
