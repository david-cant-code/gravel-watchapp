import json
import os
import sys
import tempfile
import time
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from normalize_pbw import normalize  # noqa: E402

EPOCH = 1791427443
ENTRY_TIME = time.gmtime(EPOCH)[:5] + (time.gmtime(EPOCH)[5] // 2 * 2,)


def manifest(generated_at):
    return {'manifestVersion': 2, 'generatedAt': generated_at, 'generatedBy': '', 'debug': {},
            'application': {'timestamp': EPOCH, 'name': 'pebble-app.bin', 'size': 3, 'crc': 7},
            'type': 'application'}


def bundle(path, date_time, mode, generated_at, manifest_data=None, deflated=False):
    """A PBW laid out the way the SDK's bundler writes one; deflated also varies the entries' compression and
    creating system."""
    if manifest_data is None:
        manifest_data = json.dumps(manifest(generated_at)).encode()
    with zipfile.ZipFile(path, 'w') as pbw:
        for name, data in (('appinfo.json', b'{"uuid": "x"}'), ('basalt/pebble-app.bin', b'\x01\x02\x03'),
                           ('basalt/manifest.json', manifest_data)):
            info = zipfile.ZipInfo(name, date_time)
            info.external_attr = mode << 16
            if deflated:
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 0
            pbw.writestr(info, data)


class NormalizePbwTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def path(self, name):
        return os.path.join(self.dir.name, name)

    def test_bundles_from_different_builds_come_out_identical(self):
        bundle(self.path('a.pbw'), (2026, 10, 7, 18, 51, 0), 0o100755, 1791345719)
        bundle(self.path('b.pbw'), (2026, 10, 8, 2, 52, 30), 0o100600, 1791424260, deflated=True)
        normalize(self.path('a.pbw'), self.path('a.out'), EPOCH)
        normalize(self.path('b.pbw'), self.path('b.out'), EPOCH)
        with open(self.path('a.out'), 'rb') as a, open(self.path('b.out'), 'rb') as b:
            self.assertEqual(a.read(), b.read())

    def test_keeps_entries_and_sets_times_and_permissions(self):
        bundle(self.path('in.pbw'), (2026, 10, 7, 18, 51, 0), 0o100755, 1791345719, deflated=True)
        normalize(self.path('in.pbw'), self.path('out.pbw'), EPOCH)
        with zipfile.ZipFile(self.path('in.pbw')) as src, zipfile.ZipFile(self.path('out.pbw')) as out:
            self.assertEqual(src.namelist(), out.namelist())
            for info in out.infolist():
                self.assertEqual(info.date_time, ENTRY_TIME)
                self.assertEqual(info.external_attr, 0o100644 << 16)
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                self.assertEqual(info.create_system, 3)
            self.assertEqual(out.read('appinfo.json'), src.read('appinfo.json'))
            self.assertEqual(out.read('basalt/pebble-app.bin'), src.read('basalt/pebble-app.bin'))
            written = out.read('basalt/manifest.json')
            self.assertEqual(written, json.dumps(manifest(EPOCH)).encode())

    def test_accepts_both_ends_of_the_range(self):
        bundle(self.path('in.pbw'), (2026, 10, 7, 18, 51, 0), 0o100644, 1791345719)
        for timestamp in (315532800, 2 ** 31 - 1):
            normalize(self.path('in.pbw'), self.path('out.pbw'), timestamp)
            with zipfile.ZipFile(self.path('out.pbw')) as out:
                self.assertEqual(json.loads(out.read('basalt/manifest.json'))['generatedAt'], timestamp)

    def test_rewrites_in_place(self):
        bundle(self.path('app.pbw'), (2026, 10, 7, 18, 51, 0), 0o100755, 1791345719)
        normalize(self.path('app.pbw'), self.path('app.pbw'), EPOCH)
        with zipfile.ZipFile(self.path('app.pbw')) as out:
            self.assertEqual(json.loads(out.read('basalt/manifest.json'))['generatedAt'], EPOCH)
        self.assertEqual(os.listdir(self.dir.name), ['app.pbw'])

    def test_refuses_times_outside_1980_to_2038(self):
        bundle(self.path('in.pbw'), (2026, 10, 7, 18, 51, 0), 0o100644, 1791345719)
        for timestamp in (315532799, 2 ** 31):
            with self.assertRaises(ValueError):
                normalize(self.path('in.pbw'), self.path('out.pbw'), timestamp)
        self.assertEqual(os.listdir(self.dir.name), ['in.pbw'])

    def test_leaves_no_partial_file_when_a_rewrite_fails(self):
        bundle(self.path('in.pbw'), (2026, 10, 7, 18, 51, 0), 0o100644, 1791345719, manifest_data=b'not json')
        with self.assertRaises(ValueError):
            normalize(self.path('in.pbw'), self.path('out.pbw'), EPOCH)
        self.assertEqual(os.listdir(self.dir.name), ['in.pbw'])


if __name__ == '__main__':
    unittest.main()
