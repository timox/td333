"""Round-trip tests.

These run against the factory dump ``td3dump.sqs`` when it is present
(local development), but the dump is proprietary and is NOT shipped in the
public repository. When it is absent the tests fall back to a synthetic
64-pattern bank built from the public Pattern model — license-safe and
exercising the same read/write/YAML/SysEx codecs.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from td3 import read_sqs, write_sqs, pattern_to_sysex, sysex_to_pattern
from td3.pattern import STEPS, Pattern, Step
from td3.sqs import SQSFile
from td3.yaml_io import pattern_from_yaml, pattern_to_yaml

DUMP = Path(__file__).resolve().parents[1] / "td3dump.sqs"


def _synthetic_bank() -> bytes:
    """Deterministic 64-pattern bank covering pitch range, accent, slide,
    tie, rest, triplet and varied step counts."""
    patterns: list[Pattern] = []
    for idx in range(64):
        steps: list[Step] = []
        for s in range(STEPS):
            note = 24 + ((idx * 3 + s * 5) % 37)  # stays within C1..C4 (24..60)
            steps.append(
                Step(
                    note=note,
                    rest=(s % 7 == 3),
                    accent=(s % 4 == 0),
                    slide=(s % 5 == 2),
                    tie=(s % 6 == 5),
                )
            )
        triplet = idx % 8 == 0
        patterns.append(
            Pattern(
                group=idx // 16,
                number=idx % 16,
                triplet=triplet,
                step_count=15 if triplet else (1 + idx % 16),
                steps=steps,
            )
        )
    return write_sqs(SQSFile(product="TD-3-MO", version="2.0.1", patterns=patterns))


@pytest.fixture(scope="module")
def factory_bytes() -> bytes:
    if DUMP.exists():
        return DUMP.read_bytes()
    return _synthetic_bank()


def test_sqs_byte_identical(factory_bytes: bytes) -> None:
    """Reading then writing the bank must yield the exact same bytes."""
    sqs = read_sqs(factory_bytes)
    assert len(sqs.patterns) == 64
    assert write_sqs(sqs) == factory_bytes


def test_yaml_round_trip(factory_bytes: bytes) -> None:
    """YAML serialisation must preserve every pattern byte-for-byte."""
    sqs = read_sqs(factory_bytes)
    for p in sqs.patterns:
        reloaded = pattern_from_yaml(pattern_to_yaml(p))
        assert reloaded.to_bytes() == p.to_bytes(), f"mismatch on {p.group}/{p.number}"


def test_sysex_round_trip(factory_bytes: bytes) -> None:
    """SysEx F0..F7 encoding must preserve every pattern."""
    sqs = read_sqs(factory_bytes)
    for p in sqs.patterns:
        msg = pattern_to_sysex(p)
        assert msg[0] == 0xF0 and msg[-1] == 0xF7
        assert all(b < 0x80 for b in msg[1:-1])  # 7-bit safe
        reloaded = sysex_to_pattern(msg)
        assert reloaded.to_bytes() == p.to_bytes()
        assert reloaded.group == p.group and reloaded.number == p.number
