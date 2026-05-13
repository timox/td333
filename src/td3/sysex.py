"""SysEx encoding for live MIDI exchange with the TD-3.

The TD-3 uses the Behringer manufacturer header followed by a 1-byte opcode:

    F0 00 20 32 00 01 0A <opcode> <payload...> F7

Known opcodes:
    0x77  pattern request:  payload = [group, pattern]
    0x78  pattern write/dump: payload = [group, pattern, unknown1(2), data(110)]

The 110-byte tail of the 0x78 payload is the 112-byte stored data block
without its first two bytes (those are the "unknown 1" pair, which moves into
the explicit unknown1 field of the SysEx layout — see beholder-d/td3-pattern).
All payload bytes fit in the MIDI 7-bit range because pitches/masks are stored
as nibble pairs (each byte ≤ 0x0F).
"""
from __future__ import annotations

from .pattern import DATA_SIZE, Pattern

MFR_HEADER = bytes.fromhex("00203200010A")
OP_REQUEST = 0x77
OP_WRITE   = 0x78


def request_pattern(group: int, number: int) -> bytes:
    return bytes([0xF0]) + MFR_HEADER + bytes([OP_REQUEST, group, number, 0xF7])


def pattern_to_sysex(p: Pattern) -> bytes:
    blk = p.to_bytes()
    payload = bytes([p.group, p.number]) + blk[0x00:0x02] + blk[0x02:DATA_SIZE]
    msg = bytes([0xF0]) + MFR_HEADER + bytes([OP_WRITE]) + payload + bytes([0xF7])
    if any(b & 0x80 for b in payload):
        raise ValueError("SysEx payload contains non-7-bit byte; pattern data is corrupt")
    return msg


def sysex_to_pattern(msg: bytes) -> Pattern:
    if not msg or msg[0] != 0xF0 or msg[-1] != 0xF7:
        raise ValueError("not a complete SysEx message")
    if msg[1:1 + len(MFR_HEADER)] != MFR_HEADER:
        raise ValueError("not a Behringer TD-3 SysEx message")
    body = msg[1 + len(MFR_HEADER):-1]
    if not body:
        raise ValueError("empty SysEx body")
    opcode = body[0]
    payload = body[1:]
    if opcode != OP_WRITE:
        raise ValueError(f"unsupported opcode {opcode:#04x}")
    if len(payload) != 2 + DATA_SIZE:
        raise ValueError(
            f"unexpected payload size {len(payload)} (expected {2 + DATA_SIZE})"
        )
    group, number = payload[0], payload[1]
    # Rebuild the 112-byte stored block: unknown1 (2) + remaining data (110).
    blk = bytes(payload[2:4]) + bytes(payload[4:2 + DATA_SIZE])
    return Pattern.from_bytes(group, number, blk)


def iter_sysex(buf: bytes):
    """Split a buffer of concatenated SysEx messages into individual frames."""
    i = 0
    while i < len(buf):
        if buf[i] != 0xF0:
            i += 1
            continue
        j = buf.find(b"\xf7", i)
        if j < 0:
            return
        yield buf[i:j + 1]
        i = j + 1
