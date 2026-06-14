from __future__ import annotations

from pathlib import Path
import unittest


JSFX = Path(__file__).resolve().parents[1] / "reaper" / "td3_sysex_send.jsfx"


def _source() -> str:
    return JSFX.read_text(encoding="utf-8")


class ReaperJsfxTest(unittest.TestCase):
    def test_exposes_bank_and_pattern_selection(self) -> None:
        src = _source()

        self.assertIn("Banque a jouer", src)
        self.assertIn("Pattern dans la banque", src)
        self.assertIn("function selected_pattern_index()", src)
        self.assertIn("g*16 + p", src)

    def test_midi_start_clock_is_explicit_hardware_test(self) -> None:
        src = _source()

        self.assertIn("Test sequenceur interne (FA + F8)", src)
        self.assertIn("Start sequenceur interne (pattern facade)", src)
        self.assertIn("Preview MIDI: %s     Test FA+F8: %s", src)
        self.assertIn("Le Start interne joue le pattern selectionne sur la facade TD-3.", src)

    def test_stop_seq_is_defined_before_preview_uses_it(self) -> None:
        src = _source()

        self.assertLess(
            src.index("function stop_seq()"),
            src.index("function start_preview()"),
        )


if __name__ == "__main__":
    unittest.main()
