# Pinned development source

`eng-kjv_usfx.zip` was explicitly acquired from https://ebible.org/Scriptures/eng-kjv_usfx.zip on 21 September 2026. Its SHA-256 is `6d834ebe8bcf157587ce93b774615d9e9554f1201951a072cc379930d49bb6fb`.

The original archive is unchanged. `copr.htm` is copied verbatim from the archive. The provider describes this edition as **King James Version + Apocrypha**, source ID `eng-kjv`; the full importer now uses an explicit 66-book engineering configuration. Final canon and distribution approval remain open.

Run `python3 Content/Tools/make_prototype_fixtures.py` from the repository root to reproduce the Debug-only JSON. Run `python3 -m unittest discover -s Content/Tests` for fixture validation. Conversion performs no network access. Source acquisition and full corpus conversion remain separate operations. See [content tooling](../README.md) for the full importer and machine-readable validation report.

See `prototype-manifest.json` for selection, transformations, counts, and output hash. The narrow parser records notes and headings outside verse text; it does not assert full support for every USFX marker in the archive. Release rights and territory review remain open. The application does not contact eBible.org at runtime.
