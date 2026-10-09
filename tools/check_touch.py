"""Passes an armored SSH signature only if a security key made it with a touch.

Reads the signature from stdin and checks the sk-ssh-ed25519 signature's user-presence flag, which the key signs
along with the data (openssh-portable master: PROTOCOL.sshsig, PROTOCOL.u2f "SSH U2F signatures", sk-api.h
SSH_SK_USER_PRESENCE_REQD). ssh-keygen -Y verify there only logs the flag (ssh-keygen.c sig_verify). Exit status 0
when the flag is set, 1 otherwise, including for any other key type or a malformed signature.
"""
import base64
import struct
import sys

SK_ED25519 = b'sk-ssh-ed25519@openssh.com'
USER_PRESENT = 0x01


def string(data, offset):
    length = struct.unpack_from('>I', data, offset)[0]
    end = offset + 4 + length
    if end > len(data):
        raise ValueError('truncated')
    return data[offset + 4:end], end


def touched(armor):
    lines = armor.strip().splitlines()
    if lines[0] != '-----BEGIN SSH SIGNATURE-----' or '-----END SSH SIGNATURE-----' not in lines:
        raise ValueError('not an SSH signature')
    blob = base64.b64decode(''.join(lines[1:lines.index('-----END SSH SIGNATURE-----')]), validate=True)
    if blob[:6] != b'SSHSIG':
        raise ValueError('not an SSH signature')
    offset = 10
    for _ in range(5):  # public key, namespace, reserved, hash algorithm, signature
        field, offset = string(blob, offset)
    key_type, offset = string(field, 0)
    _, offset = string(field, offset)
    if key_type != SK_ED25519 or offset >= len(field):
        return False
    return bool(field[offset] & USER_PRESENT)


if __name__ == '__main__':
    try:
        sys.exit(0 if touched(sys.stdin.read()) else 1)
    except (ValueError, IndexError, struct.error) as error:
        sys.exit('unreadable signature: {}'.format(error))
