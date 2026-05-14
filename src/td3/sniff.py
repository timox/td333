"""Interactive sniffer that maps TD-3-MO front-panel controls to MIDI messages.

Setup
-----
Connect the TD-3's **MIDI Out** (5-pin DIN or USB) to your computer's MIDI
input and run :code:`td3 ports` to see the port name, then::

    td3 sniff --port "TD-3"

The sniffer steps through each knob/switch and asks you to twist it on the
device. Whatever MIDI message the TD-3 emits is captured and labelled.

If the TD-3 turns out to be silent on its MIDI Out for most knobs (the
firmware may not transmit CCs from the physical potentiometers), the
captures will be empty for those — use :code:`td3 probe` instead to send CCs
ourselves and listen by ear for an effect.
"""
from __future__ import annotations

import json
import select
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

# Curated list of TD-3-MO controls from the official Quick Start Guide.
# Each row : (id, label, hint).  The "hint" guides the user on what to
# touch in Synthtribe (or directly on the device, if it sends anything).
TD3_CONTROLS: list[tuple[str, str, str]] = [
    # already known
    ("CUTOFF",         "VCF Cutoff (knob 2)",           "déjà connu = CC 74, sert de sanity-check"),
    # sound shaping
    ("RESONANCE",      "Resonance (knob 3)",            ""),
    ("ENV_MOD",        "Envelope Mod (knob 4)",         "modulation du filtre par l'enveloppe"),
    ("DECAY",          "Decay (knob 5)",                "temps de décroissance"),
    ("ACCENT",         "Accent (knob 6)",               "intensité des notes accentuées"),
    ("TUNE",           "VCO Tune (knob 1)",             "hauteur générale"),
    ("VOLUME",         "Volume (knob 22)",              "niveau de sortie principal"),
    # TD-3-MO additions
    ("SOFT_ATTACK",    "Soft Attack (knob 7)",          "spécifique MO"),
    ("FILTER_TRACK",   "Filter Tracking (knob 10)",     "spécifique MO"),
    ("FILTER_FM",      "Filter FM amount (knob 21)",    ""),
    ("SLIDE_TIME",     "Slide Time (knob 18)",          ""),
    ("ACCENT_SWEEP",   "Accent Sweep (knob 20)",        ""),
    ("SWEEP_SPEED",    "Sweep Speed (knob 19)",         ""),
    ("MUFFLER",        "Muffler switch (23)",           "3 positions / discrete"),
    ("ENVELOPE",       "Envelope shape (knob)",         "si présent sur MO"),
    # waveform / oscillator
    ("WAVEFORM",       "Waveform switch (15)",          "square / saw → CC ? bouton ? "),
    ("SUB_OSC",        "Sub Oscillator on/off (12)",    "interrupteur"),
    # transport / mode
    ("TEMPO",          "Tempo (knob 14)",               "probablement MIDI clock, pas un CC"),
    ("MODE",           "Mode switch (17)",              "Track Write/Play, Pattern Play/Write"),
]


@dataclass
class CaptureResult:
    control_id: str
    label: str
    msg_type: str | None = None        # "cc", "note_on", "note_off", "pitchwheel", "sysex", ...
    channel: int | None = None          # 1..16
    data: dict = field(default_factory=dict)
    raw: str = ""
    skipped: bool = False

    def as_summary(self) -> str:
        if self.skipped or not self.msg_type:
            return "skip"
        bits = [self.msg_type, f"ch{self.channel}"]
        for k, v in self.data.items():
            bits.append(f"{k}={v}")
        return " ".join(bits)


def _ensure_mido():
    try:
        import mido  # noqa: F401
        return __import__("mido")
    except ImportError as e:
        raise RuntimeError(
            "Le sniffer a besoin de mido + python-rtmidi.\n"
            "    pip install 'td3[midi]'"
        ) from e


def _msg_to_capture(msg, control_id: str, label: str) -> CaptureResult:
    out = CaptureResult(control_id=control_id, label=label,
                        msg_type=msg.type, raw=str(msg))
    if hasattr(msg, "channel"):
        out.channel = msg.channel + 1
    if msg.type == "control_change":
        out.msg_type = "cc"
        out.data = {"cc": msg.control, "value": msg.value}
    elif msg.type in ("note_on", "note_off"):
        out.data = {"note": msg.note, "velocity": msg.velocity}
    elif msg.type == "pitchwheel":
        out.data = {"pitch": msg.pitch}
    elif msg.type == "program_change":
        out.data = {"program": msg.program}
    elif msg.type == "sysex":
        out.data = {"hex": " ".join(f"{b:02X}" for b in msg.bytes())}
    return out


def _drain(port):
    while port.poll() is not None:
        pass


def _wait_for_msg(port, timeout_s: float):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        msg = port.poll()
        if msg is not None and msg.type != "clock":
            return msg
        time.sleep(0.005)
    return None


def _ask(prompt: str, default: str = "") -> str:
    sys.stdout.write(prompt)
    sys.stdout.flush()
    try:
        line = sys.stdin.readline()
    except KeyboardInterrupt:
        raise
    return (line or "").strip()


def run_sniffer(port_name: str, timeout_s: float = 8.0,
                out_path: Path | None = None) -> list[CaptureResult]:
    """Run the interactive step-by-step capture loop.

    Returns the list of captures. Saves a JSON map next to *out_path* if given.
    """
    mido = _ensure_mido()

    print(f"\nOuverture de l'entrée MIDI : {port_name!r}")
    with mido.open_input(port_name) as port:
        captures: list[CaptureResult] = []
        for control_id, label, hint in TD3_CONTROLS:
            while True:
                print("\n" + "=" * 60)
                print(f"  Contrôle : {control_id}  —  {label}")
                if hint:
                    print(f"  Indice  : {hint}")
                print("=" * 60)
                print(f"  Tourne le potard / appuie sur le bouton sur la TD-3 ({timeout_s:.0f}s timeout)…")
                print("  [Enter] capturer  [s] skip  [q] quit")

                _drain(port)
                msg = _wait_for_msg(port, timeout_s)
                if msg is None:
                    print("  (rien capturé)")
                    choice = _ask("  [r] retry  [s] skip  [q] quit  : ", "r").lower()
                    if choice == "q":
                        return captures
                    if choice == "s":
                        captures.append(CaptureResult(control_id=control_id,
                                                       label=label, skipped=True))
                        break
                    continue

                cap = _msg_to_capture(msg, control_id, label)
                print(f"  → {cap.as_summary()}   ({cap.raw})")
                choice = _ask("  [Enter] valider  [r] retry  [s] skip  : ", "").lower()
                if choice == "r":
                    continue
                if choice == "s":
                    captures.append(CaptureResult(control_id=control_id,
                                                   label=label, skipped=True))
                    break
                captures.append(cap)
                break

        if out_path is not None:
            out_path.write_text(json.dumps(
                [
                    {
                        "id": c.control_id, "label": c.label,
                        "type": c.msg_type, "channel": c.channel,
                        "data": c.data, "skipped": c.skipped, "raw": c.raw,
                    } for c in captures
                ], indent=2, ensure_ascii=False))
            print(f"\nCarte sauvegardée dans {out_path}")
        return captures


def summarise(captures: list[CaptureResult]) -> None:
    print("\n" + "=" * 60)
    print("Récapitulatif")
    print("=" * 60)
    for c in captures:
        print(f"  {c.control_id:14}  {c.as_summary()}")


# ---------------------------------------------------------------------------
# Passive monitor : dump every incoming MIDI message, optionally forward.
# Useful for sniffing Synthtribe ↔ TD-3 traffic via a virtual loopback port.
# ---------------------------------------------------------------------------

def run_monitor(port_name: str, forward_to: str | None = None,
                show_clock: bool = False) -> None:
    mido = _ensure_mido()
    fwd = mido.open_output(forward_to) if forward_to else None
    print(f"Écoute sur : {port_name!r}"
          + (f"   forward → {forward_to!r}" if forward_to else ""))
    print("Ctrl-C pour arrêter.\n")
    started = time.monotonic()
    try:
        with mido.open_input(port_name) as port:
            for msg in port:
                if not show_clock and msg.type == "clock":
                    if fwd is not None:
                        fwd.send(msg)
                    continue
                t = time.monotonic() - started
                if msg.type == "sysex":
                    hex_dump = " ".join(f"{b:02X}" for b in msg.bytes())
                    print(f"[{t:7.3f}] sysex ({len(msg.bytes())} octets) : {hex_dump}")
                else:
                    print(f"[{t:7.3f}] {msg}")
                if fwd is not None:
                    fwd.send(msg)
    except KeyboardInterrupt:
        print("\nArrêt.")
    finally:
        if fwd is not None:
            fwd.close()


# ---------------------------------------------------------------------------
# Active probe: send CCs ourselves, ask the user whether anything changes.
# Useful since Synthtribe doesn't really transmit CCs to discover from.
# ---------------------------------------------------------------------------

def run_active_probe(out_port_name: str,
                     cc_range: tuple[int, int] = (0, 127),
                     channel: int = 1,
                     out_path: Path | None = None) -> dict[int, str]:
    """Send CC <cc> with low/high values to the TD-3 and ask the user what,
    if anything, they hear changing. Returns a {cc: label} mapping of the
    CCs the user identified as having an effect.
    """
    mido = _ensure_mido()
    if not 1 <= channel <= 16:
        raise ValueError("channel must be 1..16")

    print(f"\nOuverture de la sortie MIDI : {out_port_name!r}")
    print("Conseil : maintenir une note appuyée (ou lancer une pattern simple")
    print("sur la TD-3) pour mieux entendre l'effet.\n")

    discovered: dict[int, str] = {}
    with mido.open_output(out_port_name) as port:
        for cc in range(cc_range[0], cc_range[1] + 1):
            print(f"\nCC {cc:3d}   →  envoi 0 puis 127 (deux fois) sur ch{channel}")
            for value in (0, 127, 0, 127):
                port.send(mido.Message("control_change",
                                       channel=channel - 1,
                                       control=cc,
                                       value=value))
                time.sleep(0.25)
            choice = _ask("    [Enter] rien   [n] note ce CC   [q] quit  : ", "").lower()
            if choice == "q":
                break
            if choice == "n":
                label = _ask("    quel paramètre ? (ex: Resonance) : ", "")
                discovered[cc] = label or f"CC {cc}"

    print("\nCC repérés :")
    for cc, label in discovered.items():
        print(f"  {cc:3d}  {label}")
    if out_path is not None:
        out_path.write_text(json.dumps(discovered, indent=2, ensure_ascii=False))
        print(f"\nMap sauvegardée dans {out_path}")
    return discovered
