#!/usr/bin/env python3
"""Construction ASSISTÉE + VALIDÉE d'un mapping Renoise (.xrnm).

Conçu pour ne PAS se planter :
- on ne capture QUE les pads (filtre Note strict) : un knob effleuré
  est ignoré, donc aucune collision parasite ;
- les 8 volumes encodeurs sont écrits d'office (déjà validés) → tu ne
  touches AUCUN knob pendant la capture ;
- chaque pad s'arme avec Entrée, le buffer MIDI est vidé avant la
  capture → pas de saut, pas de message résiduel ;
- compteur [k/N], confirmation, reprise propre, collision refusée ;
- à la fin : écriture du .xrnm + revalidation automatique.

Usage :
    python3 build_xrnm.py --port minilab --out minilab_renoise.xrnm
    python3 build_xrnm.py --check minilab_renoise.xrnm   # revalider

Dépend de mido + python-rtmidi.  Ctrl-C pour annuler.
"""
from __future__ import annotations

import argparse
import sys
import time
import xml.etree.ElementTree as ET

# 16 PADS à capturer (action confirmée, NoteMode). Aucune n'est devinée.
PAD_TASKS = [
    ("Pattern précédent", "Navigation:Sequencer:Select Previous Sequence Pos [Trigger]", "Trigger"),
    ("Pattern suivant",   "Navigation:Sequencer:Select Next Sequence Pos [Trigger]",     "Trigger"),
    ("Track précédente",  "Navigation:Tracks:Select Previous Track [Trigger]",           "Trigger"),
    ("Track suivante",    "Navigation:Tracks:Select Next Track [Trigger]",               "Trigger"),
    ("DSP précédent",     "Navigation:Track DSPs:Select Previous Track DSP [Trigger]",   "Trigger"),
    ("DSP suivant",       "Navigation:Track DSPs:Select Next Track DSP [Trigger]",       "Trigger"),
    ("Vue éditeur pattern", "GUI:Middle Frame:Show Pattern Editor [Trigger]",            "Trigger"),
    ("Vue éditeur MIDI",  "GUI:Middle Frame:Show Instrument Midi Editor [Trigger]",      "Trigger"),
    ("Mute Track 1", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #01 [Toggle]", "Value"),
    ("Mute Track 2", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #02 [Toggle]", "Value"),
    ("Mute Track 3", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #03 [Toggle]", "Value"),
    ("Mute Track 4", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #04 [Toggle]", "Value"),
    ("Mute Track 5", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #05 [Toggle]", "Value"),
    ("Mute Track 6", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #06 [Toggle]", "Value"),
    ("Mute Track 7", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #07 [Toggle]", "Value"),
    ("Mute Track 8", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #08 [Toggle]", "Value"),
]
# Encodeurs : écrits d'office, NON capturés (déjà validés : Volume
# tracks 1-8, canal 0-based 1 = "Ch2" affiché, CC 21..28).
ENCODERS = [
    (f"Track Levels:Volume:Track XX (Pre):Track #{i:02d} [Set]", 1, 20 + i)
    for i in range(1, 9)
]


def _mido():
    try:
        import mido
    except ImportError:
        sys.exit("mido manquant :  pip install mido python-rtmidi")
    return mido


def _resolve(ports, wanted):
    if wanted in ports:
        return wanted
    m = [p for p in ports if wanted.lower() in p.lower()]
    if len(m) == 1:
        return m[0]
    sys.exit(f"Port {wanted!r} introuvable/ambigu. Ports : {ports}")


def _ask(prompt):
    try:
        return input(prompt).strip().lower()
    except (EOFError, KeyboardInterrupt):
        print("\nAnnulé."); sys.exit(1)


def _drain(inp):
    """Vide tous les messages en attente (knobs effleurés, clock…)."""
    while inp.poll() is not None:
        pass


def _wait_pad(inp, timeout=20.0):
    """Bloque jusqu'au prochain NOTE ON (vel>0). Ignore CC/clock/sysex/
    aftertouch. Renvoie (channel0, note) ou None si timeout."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        msg = inp.poll()
        if msg is None:
            time.sleep(0.005)
            continue
        if msg.type == "note_on" and msg.velocity > 0:
            return (msg.channel, msg.note)
        # tout le reste (CC des knobs inclus) est ignoré volontairement
    return None


def build(port_fragment: str, out_path: str) -> None:
    mido = _mido()
    target = _resolve(mido.get_input_names(), port_fragment)
    n = len(PAD_TASKS)
    print(f"\nPort : {target!r}")
    print("IMPORTANT : ne touche AUCUN knob. On ne mappe que les 16 pads.")
    print("Pour chaque pad : tape Entrée pour armer, PUIS appuie le pad.\n")

    captured = []                 # (action, note_mode, ch0, note)
    used = {}                     # (ch0, note) -> libellé
    with mido.open_input(target) as inp:
        i = 0
        while i < n:
            if i == 8:
                print(">>> Bascule sur la BANQUE 9-16 (bouton Pad bank), "
                      "puis continue. <<<\n")
            label, action, note_mode = PAD_TASKS[i]
            print(f"[{i + 1}/{n}] {label}  →  appuie LE PAD…")
            _drain(inp)
            cap = _wait_pad(inp)
            if cap is None:
                print("   rien reçu — on refait.\n")
                continue
            ch0, note = cap
            msg = f"   reçu : NOTE {note} (canal {ch0 + 1})"
            if (ch0, note) in used:
                msg += f"  ⚠ déjà = « {used[(ch0, note)]} »"
            print(msg)
            if _ask("   Entrée=OK  |  r=refais : ") == "r":
                print(); continue
            used[(ch0, note)] = label
            captured.append((action, note_mode, ch0, note))
            i += 1
            print()

    _write(out_path, captured)
    print(f"✓ Écrit : {out_path}  ({len(captured)} pads + 8 encodeurs)")
    print(validate(out_path))


def _emit(lines, action, mode, ctrl, note_mode, ch0, num):
    lines += [
        '    <ActionMapping>',
        f'      <Action>{action}</Action>',
        '      <MidiMappings><MidiMapping>',
        f'        <MappingMode>{mode}</MappingMode>',
        f'        <ControllerMode>{ctrl}</ControllerMode>',
        f'        <NoteMode>{note_mode}</NoteMode>',
        f'        <Channel>{ch0}</Channel>',
        f'        <CCNumberOrNote>{num}</CCNumberOrNote>',
        '        <Min>0.0</Min><Max>1.0</Max>',
        '      </MidiMapping></MidiMappings>',
        '    </ActionMapping>',
    ]


def _write(path, pads):
    L = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<MidiActionMappingSet doc_version="0">', '  <ActionMappings>']
    for action, ch0, cc in ENCODERS:
        _emit(L, action, "Controllers", "Absolute 7 bit", "Trigger", ch0, cc)
    for action, note_mode, ch0, note in pads:
        _emit(L, action, "Notes", "Relative two's comp", note_mode, ch0, note)
    L += ['  </ActionMappings>', '</MidiActionMappingSet>', '']
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


def validate(path: str) -> str:
    out = ["\n=== Validation ==="]
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        return f"\n✗ XML invalide : {e}"
    seen, n, bad = {}, 0, 0
    for am in tree.findall(".//ActionMapping"):
        n += 1
        action = (am.findtext("Action") or "?").strip()
        mm = am.find(".//MidiMapping")
        kind = "note" if mm.findtext("MappingMode") == "Notes" else "cc"
        key = (mm.findtext("Channel"), kind, mm.findtext("CCNumberOrNote"))
        if key in seen:
            bad += 1
            out.append(f"✗ COLLISION {kind} {key[2]} ch{key[0]} : "
                       f"« {action} » ET « {seen[key]} »")
        else:
            seen[key] = action
    out.append(f"{n} mappings, {bad} collision(s).")
    out.append("✓ OK, aucun conflit." if not bad else "✗ Corrige et relance.")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("--out", default="minilab_renoise.xrnm")
    ap.add_argument("--check")
    args = ap.parse_args()
    if args.check:
        print(validate(args.check)); return
    if not args.port:
        print("Ports :", _mido().get_input_names())
        print("Relance :  --port <fragment> --out fichier.xrnm")
        return
    build(args.port, args.out)


if __name__ == "__main__":
    main()
