"""MIDI note name <-> number helpers.

Uses the convention MIDI 60 = C4. The TD-3 stores pitches one octave below
standard MIDI (per the 303patterns.com reference), so the storage value is
the MIDI number minus 12. The 0x80 bit on the storage byte is the "high C"
flag (top key on the row); the actual note number lives in the low 7 bits.
"""
from __future__ import annotations

_NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
_NAMES_FLAT  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
_LOOKUP = {n: i for i, n in enumerate(_NAMES_SHARP)} | {n: i for i, n in enumerate(_NAMES_FLAT)}


def midi_to_name(midi: int) -> str:
    return f"{_NAMES_SHARP[midi % 12]}{midi // 12 - 1}"


def name_to_midi(name: str) -> int:
    name = name.strip()
    # Find where digits start (handling negative octave like "C-1").
    for i, ch in enumerate(name):
        if ch == "-" and i > 0 and name[i + 1 :].lstrip("-").isdigit():
            note, octave = name[:i], int(name[i:])
            break
        if ch.isdigit():
            note, octave = name[:i], int(name[i:])
            break
    else:
        raise ValueError(f"invalid note name: {name!r}")
    try:
        semitone = _LOOKUP[note]
    except KeyError as e:
        raise ValueError(f"invalid pitch class: {note!r}") from e
    return (octave + 1) * 12 + semitone


# Storage encoding used by the TD-3 .sqs / SysEx pattern data.
INACTIVE_PITCH = 0x18  # placeholder used when fewer notes than slots


def midi_to_storage(midi: int) -> int:
    """MIDI number → raw 7-bit storage value (one octave lower)."""
    raw = midi - 12
    if not 0 <= raw <= 0x7F:
        raise ValueError(f"note {midi} out of range for TD-3 storage")
    return raw


def storage_to_midi(raw: int) -> int:
    """Raw storage byte → MIDI number, masking the high-C flag bit."""
    return (raw & 0x7F) + 12
