"""Run local content checks and save a machine-readable validation report."""
from pathlib import Path
import hashlib
import json
import platform
import sqlite3
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.discover(str(ROOT/'Content/Tests')))
manifest=json.loads((ROOT/'BibleReader/Resources/CorpusManifest.json').read_text())
report={'passed':result.wasSuccessful(),'testsRun':result.testsRun,'failures':[str(test) for test,_ in result.failures],
        'errors':[str(test) for test,_ in result.errors],'python':platform.python_version(),'sqlite':sqlite3.sqlite_version,
        'archiveSHA256':manifest['archiveSHA256'],'contentRevision':manifest['contentRevision'],
        'outputSHA256':hashlib.sha256((ROOT/'BibleReader/Resources/BibleCorpus.sqlite').read_bytes()).hexdigest(),
        'scope':'Offline structural, all-verse source fidelity, golden fixture, integrity, FTS, parser rejection and reproducibility checks; not rights clearance'}
folder=ROOT/'Content/Reports';folder.mkdir(exist_ok=True)
(folder/'Validation.json').write_text(json.dumps(report,indent=2)+'\n')
sys.exit(0 if result.wasSuccessful() else 1)
