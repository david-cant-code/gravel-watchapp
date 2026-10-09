"""Writes a commit's files into an empty folder exactly as git stores them.

It reads the blobs themselves, so the repository's local attributes, filters and ignore rules do not change or add
files. Refuses symlinks, submodules and unsafe paths.
Usage, inside the repository: python3 export_commit.py COMMIT FOLDER
"""
import os
import subprocess
import sys


def export(commit, folder):
    listing = subprocess.run(['git', 'ls-tree', '-r', '-z', '--full-tree', commit],
                             stdout=subprocess.PIPE, check=True).stdout
    blobs = subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for entry in filter(None, listing.split(b'\0')):
        meta, path = entry.split(b'\t', 1)
        mode, kind, oid = meta.split(b' ')
        if kind != b'blob' or mode not in (b'100644', b'100755') \
                or any(part in (b'', b'.', b'..', b'.git') for part in path.split(b'/')):
            sys.exit('cannot export {} {}'.format(mode.decode(), path.decode(errors='replace')))
        blobs.stdin.write(oid + b'\n')
        blobs.stdin.flush()
        size = int(blobs.stdout.readline().split()[2])
        data = blobs.stdout.read(size)
        blobs.stdout.read(1)
        target = os.path.join(folder, os.fsdecode(path))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, 'xb') as out:
            out.write(data)
        os.chmod(target, 0o755 if mode == b'100755' else 0o644)
    blobs.stdin.close()
    if blobs.wait():
        sys.exit('git cat-file failed')


if __name__ == '__main__':
    export(*sys.argv[1:])
