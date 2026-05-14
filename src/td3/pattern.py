"""TD-3 pattern data model and 112-byte block codec.

The TD-3 stores each pattern as a 112-byte block (the SysEx pattern data
with its leading group/pattern/unknown bytes — those move into the SQS
envelope or the SysEx payload). Field layout follows the 303patterns.com
reference and the beholder-d/td3-pattern project on GitHub:

    offset  size  field
    ------  ----  -----
    0x00     2    unknown 1   (00 00 in factory dumps; preserved verbatim)
    0x02    32    pitches     (16 entries, MSB nibble + LSB nibble per step)
    0x22    32    accent      (16 entries, same nibble encoding, value 0/1)
    0x42    32    slide       (16 entries, same nibble encoding, value 0/1)
    0x62     2    triplet     (LSB nibble = 0 or 1)
    0x64     2    step count  (MSB nibble + LSB nibble; "01 00" = 16 steps)
    0x66     2    unknown 2   (00 00 in factory dumps)
    0x68     4    hold mask   (low-nibble layout 7654/3210/FEDC/BA98)
    0x6C     4    rest mask   (same low-nibble layout)

Pitches / accent / slide are currently treated as INDEXED BY STEP (entry i
corresponds to step i). Rest mask separately marks which steps are
silenced; the stored pitch for a rest step is preserved verbatim (typically
0x18 when the slot was never programmed, but can be any value — for example
from a previous edit).

⚠️ Open question / TODO: the beholder-d/td3-pattern project notes that on
the TD-3 firmware, "Note/Transpose/Accent/Slide advance differently than
Tie/Rest when entering a pattern", which strongly suggests the firmware
actually uses a PACKED model — pitches[0..N-1] are the active notes in
playing order (N = step_count − rest count), and the rest mask alone
positions silences inside the 16 steps. The factory dump td3dump.sqs is
consistent with this: pattern 0/0 has 9 real pitches at the start of the
buffer followed by 7 0x18 placeholders, while the rest mask scatters 7
rests across the 16 steps.

Round-trip of factory data is byte-exact under either model because we
both read and write the same bytes; the semantic discrepancy only shows up
when *creating* a new pattern with rests in the middle. To finalise the
correct model, send a synthetic pattern with a single rest mid-row and
listen to which step actually plays the next note on hardware.

Hold mask uses INVERTED semantics: bit set (1) = normal note, bit clear (0) =
held / tied to the previous step (the TD-3 firmware ignores the held step's
own data and inherits the previous step's pitch/accent/slide). All-ones
(0F 0F 0F 0F) means "no ties anywhere", which is the factory default.

Each stored pitch is a 7-bit storage value (the MIDI number minus 12 — the
303patterns reference describes this as "one octave lower than standard
MIDI"). The TD-3 keyboard covers 3 octaves: storage 0x0C..0x30 (C1..C4).
0x18 (= MIDI 36 = C2) is the firmware's idle default.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

from .notes import INACTIVE_PITCH, midi_to_storage, storage_to_midi

DATA_SIZE = 112
STEPS = 16
DEFAULT_NOTE_MIDI = storage_to_midi(INACTIVE_PITCH)  # 36 = C2


@dataclass
class Step:
    note: int = DEFAULT_NOTE_MIDI
    rest: bool = False
    accent: bool = False
    slide: bool = False
    tie: bool = False


@dataclass
class Pattern:
    group: int = 0              # 0..3 (A..D)
    number: int = 0             # 0..15
    triplet: bool = False
    step_count: int = 16        # 1..16 (12 in triplet mode)
    steps: list[Step] = field(default_factory=lambda: [Step(rest=True) for _ in range(STEPS)])
    unknown1: bytes = b"\x00\x00"
    unknown2: bytes = b"\x00\x00"

    # ---- decode ------------------------------------------------------------

    @classmethod
    def from_bytes(cls, group: int, number: int, blk: bytes) -> "Pattern":
        if len(blk) != DATA_SIZE:
            raise ValueError(f"pattern block must be {DATA_SIZE} bytes, got {len(blk)}")
        unknown1 = bytes(blk[0x00:0x02])
        pitches  = _decode_pairs(blk[0x02:0x22])
        accent   = _decode_pairs(blk[0x22:0x42])
        slide    = _decode_pairs(blk[0x42:0x62])
        triplet  = bool(((blk[0x62] << 4) | blk[0x63]) & 0xFF)
        step_count = ((blk[0x64] << 4) | blk[0x65]) & 0xFF
        if step_count == 0:
            step_count = 16
        unknown2 = bytes(blk[0x66:0x68])
        # Hold mask is INVERTED: bit=0 → step is tied to previous; bit=1 → normal.
        hold_bits = _decode_step_mask(blk[0x68:0x6C])
        rest_mask = _decode_step_mask(blk[0x6C:0x70])

        steps = [
            Step(
                note=storage_to_midi(pitches[i]),
                rest=rest_mask[i],
                accent=bool(accent[i] & 1),
                slide=bool(slide[i] & 1),
                tie=not hold_bits[i],
            )
            for i in range(STEPS)
        ]
        return cls(
            group=group, number=number, triplet=triplet, step_count=step_count,
            steps=steps, unknown1=unknown1, unknown2=unknown2,
        )

    # ---- encode ------------------------------------------------------------

    def to_bytes(self) -> bytes:
        if len(self.unknown1) != 2 or len(self.unknown2) != 2:
            raise ValueError("unknown1/unknown2 must be 2 bytes each")
        if len(self.steps) != STEPS:
            raise ValueError(f"pattern needs exactly {STEPS} steps")
        # Triplet quirk: the firmware (and Synthtribe) rejects step_count=16
        # in triplet mode — slides stop working and attacks are swallowed.
        # We mirror Synthtribe's normalisation : clamp to 15 and force the
        # 16th step into a held placeholder. Round-trip of factory patterns
        # is unaffected since none of them use that combo.
        if self.triplet and self.step_count > 15:
            self.step_count = 15
            self.steps[15] = Step(
                rest=False,
                note=DEFAULT_NOTE_MIDI,
                accent=False,
                slide=False,
                tie=True,
            )
        pitches = [midi_to_storage(s.note) for s in self.steps]
        accent  = [1 if s.accent else 0   for s in self.steps]
        slide   = [1 if s.slide  else 0   for s in self.steps]
        rest_bits = [s.rest for s in self.steps]
        # Invert tie → hold mask (bit=1 means "normal", bit=0 means "tied").
        hold_bits = [not s.tie for s in self.steps]

        out = bytearray(DATA_SIZE)
        out[0x00:0x02] = self.unknown1
        out[0x02:0x22] = _encode_pairs(pitches)
        out[0x22:0x42] = _encode_pairs(accent)
        out[0x42:0x62] = _encode_pairs(slide)
        out[0x62] = 0x00
        out[0x63] = 0x01 if self.triplet else 0x00
        sc = self.step_count
        out[0x64] = (sc >> 4) & 0x0F
        out[0x65] = sc & 0x0F
        out[0x66:0x68] = self.unknown2
        out[0x68:0x6C] = _encode_step_mask(hold_bits)
        out[0x6C:0x70] = _encode_step_mask(rest_bits)
        return bytes(out)


# ---------- low-level codecs ------------------------------------------------

def _decode_pairs(b: bytes) -> list[int]:
    return [((b[i] & 0x0F) << 4) | (b[i + 1] & 0x0F) for i in range(0, len(b), 2)]


def _encode_pairs(values: Iterable[int]) -> bytes:
    out = bytearray()
    for v in values:
        out.append((v >> 4) & 0x0F)
        out.append(v & 0x0F)
    return bytes(out)


# Step-mask layout: 4 bytes, low nibble of each used.
#   byte 0 → steps 7,6,5,4   (MSB..LSB of nibble)
#   byte 1 → steps 3,2,1,0
#   byte 2 → steps F,E,D,C
#   byte 3 → steps B,A,9,8
_MASK_LAYOUT = (
    (7, 6, 5, 4),
    (3, 2, 1, 0),
    (15, 14, 13, 12),
    (11, 10, 9, 8),
)


def _decode_step_mask(b: bytes) -> list[bool]:
    bits = [False] * STEPS
    for byte_i, steps in enumerate(_MASK_LAYOUT):
        nib = b[byte_i] & 0x0F
        for bit_i, step in enumerate(steps):
            bits[step] = bool(nib & (0x08 >> bit_i))
    return bits


def _encode_step_mask(bits: list[bool]) -> bytes:
    out = bytearray(4)
    for byte_i, steps in enumerate(_MASK_LAYOUT):
        nib = 0
        for bit_i, step in enumerate(steps):
            if bits[step]:
                nib |= 0x08 >> bit_i
        out[byte_i] = nib
    return bytes(out)
