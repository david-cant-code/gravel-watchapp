"""Rewrites a PBW so that the same app gives the same bytes.

Usage: normalize_pbw.py <in.pbw> <out.pbw> <seconds since the epoch>

The SDK's bundler records the time of the build in each manifest's generatedAt, and each file's modification time
and permissions in its zip entry (sdk-core 4.33.1 common/tools/mkbundle.py, PebbleBundle). This keeps the
entries, their order and their contents, sets those times from the given time and the permissions to 0644.
"""

import json
import os
import sys
import time
import zipfile

# 1980-01-01 UTC, the earliest date a zip entry can record.
ZIP_EPOCH = 315532800
# Gravel reads the manifest's times as signed 32-bit numbers (libpebble3 PbwManifest, PbwBlob).
MAX_TIMESTAMP = 2 ** 31 - 1


def normalize(src, dst, timestamp):
    if not ZIP_EPOCH <= timestamp <= MAX_TIMESTAMP:
        raise ValueError('{} is outside {}..{}'.format(timestamp, ZIP_EPOCH, MAX_TIMESTAMP))
    date_time = time.gmtime(timestamp)[:6]
    with zipfile.ZipFile(src) as pbw:
        entries = [(info.filename, pbw.read(info)) for info in pbw.infolist()]
    tmp = dst + '.tmp'
    try:
        with zipfile.ZipFile(tmp, 'w') as pbw:
            for name, data in entries:
                if os.path.basename(name) == 'manifest.json':
                    manifest = json.loads(data)
                    manifest['generatedAt'] = timestamp
                    data = json.dumps(manifest).encode()
                info = zipfile.ZipInfo(name, date_time)
                info.external_attr = 0o100644 << 16
                pbw.writestr(info, data)
        os.replace(tmp, dst)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().splitlines()[2])
    normalize(sys.argv[1], sys.argv[2], int(sys.argv[3]))
