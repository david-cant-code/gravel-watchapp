"""Makes sk-ssh-ed25519 SSH signatures in software, with any flags byte, for the release check's tests.

`sk_sign.py key SEED` prints the public key as allowed_signers takes it, for a 32-byte hex seed.
`sk_sign.py sign SEED FLAGS` prints the armored signature of stdin in the git namespace.
Layouts follow openssh-portable master PROTOCOL.sshsig and PROTOCOL.u2f; Ed25519 follows RFC 8032 section 5.1.
"""
import base64
import hashlib
import struct
import sys

P = 2 ** 255 - 19
L = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
KEY_TYPE = b'sk-ssh-ed25519@openssh.com'
APPLICATION = b'ssh:'


def add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    pa, pb = (y1 - x1) * (y2 - x2) % P, (y1 + x1) * (y2 + x2) % P
    pc, pd = 2 * t1 * t2 * D % P, 2 * z1 * z2 % P
    e, f, g, h = pb - pa, pd - pc, pd + pc, pb + pa
    return e * f % P, g * h % P, f * g % P, e * h % P


def multiply(scalar, point):
    result = (0, 1, 1, 0)
    while scalar:
        if scalar & 1:
            result = add(result, point)
        point = add(point, point)
        scalar >>= 1
    return result


def base_point():
    y = 4 * pow(5, P - 2, P) % P
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * pow(2, (P - 1) // 4, P) % P
    if x & 1:
        x = P - x
    return x, y, 1, x * y % P


def encode(point):
    inverse = pow(point[2], P - 2, P)
    x, y = point[0] * inverse % P, point[1] * inverse % P
    return (y | (x & 1) << 255).to_bytes(32, 'little')


def expand(seed):
    digest = hashlib.sha512(seed).digest()
    scalar = int.from_bytes(digest[:32], 'little') & ((1 << 254) - 8) | (1 << 254)
    return scalar, digest[32:], encode(multiply(scalar, base_point()))


def ed25519(seed, message):
    scalar, prefix, public = expand(seed)
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), 'little') % L
    encoded_r = encode(multiply(r, base_point()))
    k = int.from_bytes(hashlib.sha512(encoded_r + public + message).digest(), 'little') % L
    return encoded_r + ((r + k * scalar) % L).to_bytes(32, 'little')


def string(data):
    return struct.pack('>I', len(data)) + data


def public_key(seed):
    return string(KEY_TYPE) + string(expand(seed)[2]) + string(APPLICATION)


def sign(seed, flags, data):
    fields = string(b'git') + string(b'') + string(b'sha512')
    signed = b'SSHSIG' + fields + string(hashlib.sha512(data).digest())
    tail = bytes([flags]) + struct.pack('>I', 1)
    raw = ed25519(seed, hashlib.sha256(APPLICATION).digest() + tail + hashlib.sha256(signed).digest())
    signature = string(KEY_TYPE) + string(raw) + tail
    blob = b'SSHSIG' + struct.pack('>I', 1) + string(public_key(seed)) + fields + string(signature)
    text = base64.b64encode(blob).decode()
    lines = [text[i:i + 70] for i in range(0, len(text), 70)]
    return '\n'.join(['-----BEGIN SSH SIGNATURE-----'] + lines + ['-----END SSH SIGNATURE-----']) + '\n'


if __name__ == '__main__':
    seed = bytes.fromhex(sys.argv[2])
    if sys.argv[1] == 'key':
        print(KEY_TYPE.decode(), base64.b64encode(public_key(seed)).decode())
    else:
        sys.stdout.write(sign(seed, int(sys.argv[3], 0), sys.stdin.buffer.read()))
