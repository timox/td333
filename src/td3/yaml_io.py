"""Human-friendly YAML serialisation for TD-3 patterns.

Each pattern is one YAML file. A step is a string of whitespace-separated
tokens: the first token is the pitch (a note name like "F#3", or "-" for a
silent rest with the default placeholder pitch) and the remaining tokens are
flags from {accent, slide, tie, rest}. Single-letter aliases on input:
"!" = accent, "~" = slide, "^" = tie.

A pitch followed by the "rest" flag silences the step while preserving the
stored pitch byte — useful for round-tripping factory patterns that hold a
ghost pitch under a rest step.

Example::

    group: A
    pattern: 1
    triplet: false
    step_count: 16
    seq:
      -  "F#3 slide"
      -  "E3 slide"
      -  "D3 rest"          # silent but stored pitch is D3
      -  "B2"
      -  "D3 slide"
      -  "G#2 rest"
      -  "D3 rest"
      -  "F#2 rest"
      -  "B3 slide"
      -  "-"                # silent, default placeholder pitch
      -  "-"
      -  "-"
      -  "-"
      -  "-"
      -  "-"
      -  "-"

Group can be written as the letter (A..D) or the integer (0..3); pattern
as 1..16 (one-based, friendlier) or 0..15.
"""
from __future__ import annotations

from typing import Any

import yaml

from .notes import midi_to_name, name_to_midi
from .pattern import DEFAULT_NOTE_MIDI, STEPS, Pattern, Step

_GROUP_LETTERS = "ABCD"
_FLAG_ALIASES = {
    "accent": "accent", "!": "accent", "a": "accent",
    "slide":  "slide",  "~": "slide",  "s": "slide",
    "tie":    "tie",    "^": "tie",    "t": "tie",
    "rest":   "rest",
}


# ---- serialisation ---------------------------------------------------------

def _step_token(s: Step) -> str:
    # A rest step with the default placeholder pitch collapses to "-".
    if s.rest and s.note == DEFAULT_NOTE_MIDI and not (s.accent or s.slide or s.tie):
        return "-"
    parts = [midi_to_name(s.note)]
    if s.accent: parts.append("accent")
    if s.slide:  parts.append("slide")
    if s.tie:    parts.append("tie")
    if s.rest:   parts.append("rest")
    return " ".join(parts)


def pattern_to_yaml(p: Pattern) -> str:
    data: dict[str, Any] = {
        "group":      _GROUP_LETTERS[p.group],
        "pattern":    p.number + 1,
        "triplet":    p.triplet,
        "step_count": p.step_count,
        "seq":        [_step_token(s) for s in p.steps],
    }
    # Preserve opaque bytes only when they deviate from the common defaults,
    # so hand-written YAML stays clean.
    if p.unknown1 != b"\x00\x00":
        data["_unknown1"] = p.unknown1.hex()
    if p.unknown2 != b"\x00\x00":
        data["_unknown2"] = p.unknown2.hex()
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True)


# ---- parsing ---------------------------------------------------------------

def _parse_group(v: Any) -> int:
    if isinstance(v, int):
        if not 0 <= v <= 3:
            raise ValueError(f"group {v} out of range 0..3")
        return v
    if isinstance(v, str) and len(v) == 1 and v.upper() in _GROUP_LETTERS:
        return _GROUP_LETTERS.index(v.upper())
    raise ValueError(f"invalid group {v!r}; use A..D or 0..3")


def _parse_pattern_num(v: Any) -> int:
    if not isinstance(v, int):
        raise ValueError(f"pattern must be an integer, got {v!r}")
    if 1 <= v <= 16:
        return v - 1
    if 0 <= v <= 15:
        return v
    raise ValueError(f"pattern {v} out of range 1..16 (or 0..15)")


def _parse_step(token: Any, index: int) -> Step:
    if token is None:
        return Step(rest=True)
    s = str(token).strip()
    if not s or s == "-":
        return Step(rest=True)
    parts = s.split()
    head, flags = parts[0], parts[1:]
    canonical: set[str] = set()
    for f in flags:
        key = _FLAG_ALIASES.get(f.lower())
        if key is None:
            raise ValueError(f"step {index + 1}: unknown flag {f!r}")
        canonical.add(key)
    return Step(
        note=name_to_midi(head),
        rest="rest" in canonical,
        accent="accent" in canonical,
        slide="slide" in canonical,
        tie="tie" in canonical,
    )


def pattern_from_yaml(text: str) -> Pattern:
    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        raise ValueError("YAML root must be a mapping")
    group = _parse_group(doc.get("group", 0))
    number = _parse_pattern_num(doc.get("pattern", 1))
    triplet = bool(doc.get("triplet", False))
    step_count = int(doc.get("step_count", 16))
    if not 1 <= step_count <= 16:
        raise ValueError(f"step_count {step_count} out of range 1..16")
    seq = doc.get("seq", [])
    if not isinstance(seq, list):
        raise ValueError("seq must be a list")
    steps = [_parse_step(seq[i] if i < len(seq) else None, i) for i in range(STEPS)]
    unknown1 = bytes.fromhex(doc["_unknown1"]) if "_unknown1" in doc else b"\x00\x00"
    unknown2 = bytes.fromhex(doc["_unknown2"]) if "_unknown2" in doc else b"\x00\x00"
    return Pattern(
        group=group, number=number, triplet=triplet, step_count=step_count,
        steps=steps, unknown1=unknown1, unknown2=unknown2,
    )
