#!/usr/bin/env python3
"""Build a deterministic ZIP. No dependency install, credentials or Azure access."""
import hashlib, json, zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = root / '.build'
out.mkdir(exist_ok=True)
archive = out / 'function.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted((root / 'function').rglob('*')):
        if path.is_file():
            info = zipfile.ZipInfo(path.relative_to(root / 'function').as_posix(), (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, path.read_bytes())
print(json.dumps({'path': str(archive), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))
