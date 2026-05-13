"""Round-trip tests against the factory dump."""
from __future__ import annotations

from pathlib import Path

import pytest

from td3 import read_sqs, write_sqs, pattern_to_sysex, sysex_to_pattern
from td3.yaml_io import pattern_from_yaml, pattern_to_yaml

DUMP = Path(__file__).resolve().parents[1] / "td3dump.sqs"


@pytest.fixture(scope="module")
def factory_bytes() -> bytes:
    return DUMP.read_bytes()


def test_sqs_byte_identical(factory_bytes: bytes) -> None:
    """Reading then writing the factory dump must yield the exact same bytes."""
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
