"""Read / write the Behringer .sqs container produced by Synthtribe.

File layout (observed on a TD-3 factory dump):

    offset  size  field
    ------  ----  -----
    0x00    4     magic 87 43 91 02
    0x04    4     UTF-16BE string length in bytes (big-endian uint32)
    0x08    N     UTF-16BE product code (e.g. "TD-3-MO")
    +0      4     UTF-16BE string length
    +4      M     UTF-16BE firmware version (e.g. "2.0.1")
    ...     64 × pattern records of 12 + 112 = 124 bytes each:
                  uint32 group, uint32 pattern, uint32 size (always 0x70=112),
                  followed by the 112-byte pattern data block.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

from .pattern import DATA_SIZE, Pattern

MAGIC = b"\x87\x43\x91\x02"
RECORD_SIZE_FIELD = 0x70  # = DATA_SIZE


@dataclass
class SQSFile:
    product: str
    version: str
    patterns: list[Pattern]


def _read_utf16be_string(buf: bytes, off: int) -> tuple[str, int]:
    n = struct.unpack_from(">I", buf, off)[0]
    off += 4
    s = buf[off:off + n].decode("utf-16-be")
    return s, off + n


def _write_utf16be_string(s: str) -> bytes:
    encoded = s.encode("utf-16-be")
    return struct.pack(">I", len(encoded)) + encoded


def read_sqs(buf: bytes) -> SQSFile:
    if buf[:4] != MAGIC:
        raise ValueError(f"not a .sqs file (magic {buf[:4].hex()})")
    off = 4
    product, off = _read_utf16be_string(buf, off)
    version, off = _read_utf16be_string(buf, off)

    patterns: list[Pattern] = []
    while off < len(buf):
        if off + 12 > len(buf):
            raise ValueError(f"truncated record header at offset {off:#x}")
        group, number, size = struct.unpack_from(">III", buf, off)
        off += 12
        if size != DATA_SIZE:
            raise ValueError(
                f"unexpected record size {size} (expected {DATA_SIZE}) at offset {off:#x}"
            )
        blk = buf[off:off + size]
        off += size
        patterns.append(Pattern.from_bytes(group, number, blk))
    return SQSFile(product=product, version=version, patterns=patterns)


def write_sqs(sqs: SQSFile) -> bytes:
    out = bytearray(MAGIC)
    out += _write_utf16be_string(sqs.product)
    out += _write_utf16be_string(sqs.version)
    for p in sqs.patterns:
        blk = p.to_bytes()
        out += struct.pack(">III", p.group, p.number, len(blk))
        out += blk
    return bytes(out)
