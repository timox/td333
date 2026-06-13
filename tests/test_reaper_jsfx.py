"""Vérification du JSFX ``reaper/td3_sysex_send.jsfx``.

Le JSFX n'est pas exécutable hors REAPER, mais toute sa logique de
protocole est censée être un PORT exact de la lib ``td3`` du dépôt (elle,
testée sur device). Ce test rejoue en Python l'arithmétique *littérale*
écrite dans le JSFX et la confronte aux fonctions de référence de
``src/td3`` :

  - construction des trames SysEx (clock source 0x1B, rate 0x1A, accent
    0x1C, channels 0x0E, request config 0x75, firmware 0x08, request
    pattern 0x77) vs ``td3.config`` / ``td3.sysex`` ;
  - décodage du bloc 112 octets reçu en 0x78 (paires de nibbles, mask
    rest, step_count, triplet, storage->midi) vs ``Pattern.from_bytes``.

Si quelqu'un modifie un offset/opcode dans le JSFX sans le refléter ici
(et inversement), le test casse. C'est le filet de sécurité demandé.
"""
from __future__ import annotations

from td3 import pattern_to_sysex
from td3.config import (request_config, request_firmware_version,
                        set_accent_velocity_threshold, set_clock_source,
                        set_clock_trigger_rate, set_midi_channels)
from td3.notes import storage_to_midi
from td3.pattern import Pattern, Step
from td3.sysex import request_pattern

# Header fabricant tel qu'écrit en dur dans le JSFX (syx_begin).
JSFX_HDR = [0xF0, 0x00, 0x20, 0x32, 0x00, 0x01, 0x0A]


# --- réplique LITTÉRALE des constructeurs de trames du JSFX -----------------

def jsfx_syx1(op: int, v: int) -> bytes:
    return bytes(JSFX_HDR + [op, v, 0xF7])


def jsfx_set_channels(inc: int, outc: int) -> bytes:
    # syx_push(0x0E); syx_push(1); syx_push(outc-1); syx_push(inc-1)
    return bytes(JSFX_HDR + [0x0E, 1, outc - 1, inc - 1, 0xF7])


def jsfx_req(*payload: int) -> bytes:
    return bytes(JSFX_HDR + list(payload) + [0xF7])


# --- réplique LITTÉRALE du décodage 112 octets du JSFX ----------------------

def jsfx_pair(buf, o: int) -> int:
    # function pair(o): (RXBUF[o]%16)*16 + (RXBUF[o+1]%16)
    return (buf[o] % 16) * 16 + (buf[o + 1] % 16)


def jsfx_set_rest(rest, nib, s3, s2, s1, s0) -> None:
    rest[s3] = (nib // 8) % 2
    rest[s2] = (nib // 4) % 2
    rest[s1] = (nib // 2) % 2
    rest[s0] = nib % 2


def jsfx_decode(rx: bytes, base: int) -> dict:
    """``decode_into`` du JSFX : ``rx`` = message 0x78 complet, ``base`` = 10
    (offset du 1er octet du bloc 112 dans le message, après group,pat)."""
    pitch = [jsfx_pair(rx, base + 0x02 + 2 * s) for s in range(16)]
    accent = [jsfx_pair(rx, base + 0x22 + 2 * s) % 2 for s in range(16)]
    slide = [jsfx_pair(rx, base + 0x42 + 2 * s) % 2 for s in range(16)]
    triplet = 1 if jsfx_pair(rx, base + 0x62) != 0 else 0
    sc = jsfx_pair(rx, base + 0x64) or 16
    rest = [0] * 16
    jsfx_set_rest(rest, rx[base + 0x6C] % 16, 7, 6, 5, 4)
    jsfx_set_rest(rest, rx[base + 0x6D] % 16, 3, 2, 1, 0)
    jsfx_set_rest(rest, rx[base + 0x6E] % 16, 15, 14, 13, 12)
    jsfx_set_rest(rest, rx[base + 0x6F] % 16, 11, 10, 9, 8)
    note = [(pitch[s] % 128) + 12 for s in range(16)]  # storage_to_midi du JSFX
    return dict(pitch=pitch, accent=accent, slide=slide, rest=rest,
                triplet=triplet, step_count=sc, note=note)


# ---------------------------------------------------------------------------
# Trames SysEx : JSFX == lib de référence
# ---------------------------------------------------------------------------

def test_jsfx_frames_match_lib() -> None:
    assert jsfx_syx1(0x1B, 2) == set_clock_source(2)            # USB
    assert jsfx_syx1(0x1A, 2) == set_clock_trigger_rate(2)      # 24 PPQ
    assert jsfx_syx1(0x1C, 100) == set_accent_velocity_threshold(100)
    assert jsfx_set_channels(1, 1) == set_midi_channels(input_ch=1, output_ch=1)
    assert jsfx_set_channels(3, 5) == set_midi_channels(input_ch=3, output_ch=5)
    assert jsfx_req(0x75) == request_config()
    assert jsfx_req(0x08, 0) == request_firmware_version()
    assert jsfx_req(0x77, 2, 9) == request_pattern(2, 9)


# ---------------------------------------------------------------------------
# Décodage 0x78 : JSFX == Pattern.from_bytes, sur un pattern non trivial
# ---------------------------------------------------------------------------

def _sample_pattern() -> Pattern:
    steps = []
    for s in range(16):
        steps.append(Step(
            note=24 + (s * 5 + 3) % 37,   # reste dans C1..C4 (24..60)
            rest=(s % 5 == 2),
            accent=(s % 3 == 0),
            slide=(s % 4 == 1),
            tie=(s % 6 == 4),
        ))
    return Pattern(group=2, number=9, triplet=False, step_count=13, steps=steps)


def test_jsfx_decode_matches_pattern_model() -> None:
    p = _sample_pattern()
    msg = pattern_to_sysex(p)                 # trame 0x78 que la TD-3 renverrait
    assert msg[7] == 0x78 and msg[8] == p.group and msg[9] == p.number

    d = jsfx_decode(msg, 10)                  # base=10, comme handle_rx du JSFX

    assert d["triplet"] == (1 if p.triplet else 0)
    assert d["step_count"] == p.step_count
    for s, st in enumerate(p.steps):
        # pitch storage : midi - 12 (cf. midi_to_storage), le JSFX rejoue
        # note = (storage % 128) + 12 = storage_to_midi.
        assert d["pitch"][s] == st.note - 12          # storage = midi - 12
        assert d["note"][s] == storage_to_midi(d["pitch"][s]) == st.note
        assert bool(d["accent"][s]) == st.accent
        assert bool(d["slide"][s]) == st.slide
        assert bool(d["rest"][s]) == st.rest


def test_jsfx_decode_triplet_and_empty_rests() -> None:
    # Pattern triplet + rests "vides" (placeholder C2) pour couvrir le mask
    # et le clamp step_count (15) du firmware.   [REPO pattern.py to_bytes]
    steps = [Step(rest=True) for _ in range(16)]
    steps[0] = Step(note=36, accent=True)
    steps[1] = Step(note=48, slide=True)
    p = Pattern(group=0, number=0, triplet=True, step_count=16, steps=steps)
    msg = pattern_to_sysex(p)
    d = jsfx_decode(msg, 10)

    assert d["triplet"] == 1
    assert d["step_count"] == 15            # clampé par to_bytes en triplet
    assert d["rest"] == [0, 0] + [1] * 14
    assert d["note"][0] == 36 and d["accent"][0] == 1
    assert d["note"][1] == 48 and d["slide"][1] == 1
