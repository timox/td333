#!/usr/bin/env python3
"""Dumper MIDI autonome — identifier ce qu'envoie chaque contrôle.

Usage :

    # 1. Lister les ports d'entrée disponibles
    python3 midi_dump.py

    # 2. Écouter un port (fragment de nom suffit, ex. "minilab")
    python3 midi_dump.py --port minilab

Appuie/tourne chaque pad, knob, touche : chaque message est décodé avec
le canal MIDI **affiché par Renoise** (1-based) et un libellé. Idéal
pour relever les Note/CC de la 2e banque de pads.

Dépend de `mido` + `python-rtmidi` :  pip install mido python-rtmidi
(ou, dans ce repo :  pip install -e ".[midi]")

Ctrl-C pour quitter.
"""
from __future__ import annotations

import argparse
import sys
import time


def _import_mido():
    try:
        import mido  # noqa: F401
    except ImportError:
        sys.exit(
            "mido introuvable. Installe :  pip install mido python-rtmidi\n"
            "(ou depuis le repo :  pip install -e \".[midi]\")"
        )
    import mido
    return mido


def _resolve(ports: list[str], wanted: str) -> str:
    if wanted in ports:
        return wanted
    matches = [p for p in ports if wanted.lower() in p.lower()]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        sys.exit(f"Aucun port ne contient {wanted!r}. Ports : {ports}")
    sys.exit(f"{wanted!r} ambigu, précise : {matches}")


def _describe(msg) -> str:
    """Libellé lisible + suggestion d'usage pour le mapping Renoise."""
    t = msg.type
    if t in ("note_on", "note_off"):
        on = t == "note_on" and msg.velocity > 0
        return (
            f"NOTE {'ON ' if on else 'OFF'} "
            f"note={msg.note:<3} vel={msg.velocity:<3} "
            f"ch={msg.channel + 1:<2}  "
            f"→ .xrnm: <Channel>{msg.channel}</Channel> "
            f"<CCNumberOrNote>{msg.note}</CCNumberOrNote> (MappingMode Notes)"
        )
    if t == "control_change":
        return (
            f"CC          cc={msg.control:<3} val={msg.value:<3} "
            f"ch={msg.channel + 1:<2}  "
            f"→ .xrnm: <Channel>{msg.channel}</Channel> "
            f"<CCNumberOrNote>{msg.control}</CCNumberOrNote> "
            f"(MappingMode Controllers)"
        )
    if t == "program_change":
        return f"PROGRAM CHANGE program={msg.program} ch={msg.channel + 1}"
    if t == "pitchwheel":
        return f"PITCH BEND   value={msg.pitch} ch={msg.channel + 1}"
    if t == "sysex":
        data = " ".join(f"{b:02X}" for b in msg.data)
        arturia = msg.data[:3] == (0x00, 0x20, 0x6B)
        tag = "  [Arturia interne — non mappable, ignorer]" if arturia else ""
        return f"SYSEX        {data}{tag}"
    return f"{t}: {msg}"


def main() -> None:
    mido = _import_mido()
    ap = argparse.ArgumentParser(description="Dumper MIDI (identification de contrôles)")
    ap.add_argument("--port", help="Nom (ou fragment) du port MIDI d'entrée")
    args = ap.parse_args()

    ports = mido.get_input_names()
    if not args.port:
        print("Ports MIDI d'entrée :")
        for p in ports:
            print(f"  - {p}")
        print("\nRelance avec :  python3 midi_dump.py --port <fragment>")
        return

    target = _resolve(ports, args.port)
    print(f"Écoute de {target!r}. Appuie/tourne chaque contrôle. Ctrl-C pour quitter.\n")
    with mido.open_input(target) as inp:
        try:
            for msg in inp:
                ts = time.strftime("%H:%M:%S")
                print(f"[{ts}] {_describe(msg)}")
        except KeyboardInterrupt:
            print("\nFin.")


if __name__ == "__main__":
    main()
