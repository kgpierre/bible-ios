"""Explicit acquisition only; app builds and tests never invoke this script."""
from pathlib import Path
import hashlib
import tempfile
import urllib.request

DESTINATION = Path(__file__).resolve().parents[1] / 'Source/eng-kjv_usfx.zip'
URL = 'https://ebible.org/Scriptures/eng-kjv_usfx.zip'
PIN = '6d834ebe8bcf157587ce93b774615d9e9554f1201951a072cc379930d49bb6fb'

def acquire():
    if DESTINATION.exists():
        if hashlib.sha256(DESTINATION.read_bytes()).hexdigest() != PIN:
            raise ValueError('Existing archive differs from pin; preserve and review it manually')
        print('Verified existing pinned source; no download needed.')
        return
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(10_000_001)
    if len(data) > 10_000_000 or hashlib.sha256(data).hexdigest() != PIN:
        raise ValueError('Remote archive has changed or exceeds limit; review before changing the pin')
    DESTINATION.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=DESTINATION.parent,delete=False) as file:
        file.write(data)
        temporary=Path(file.name)
    temporary.replace(DESTINATION)
    print('Acquired and verified pinned source.')

if __name__=='__main__': acquire()
