#!/usr/bin/env python3
"""Construction ASSISTÉE + VALIDÉE d'un mapping Renoise (.xrnm).

But : supprimer la saisie manuelle (source d'erreurs). L'outil te
demande, fonction par fonction, d'appuyer sur le pad / tourner le knob
voulu, capture le message MIDI réel, te fait CONFIRMER, détecte les
collisions et REPREND si besoin, puis écrit le .xrnm et le REVALIDE.

Usage :

    # Construire interactivement (capture → confirme → écrit → valide)
    python3 build_xrnm.py --port minilab --out minilab_renoise.xrnm

    # Seulement revalider un .xrnm existant
    python3 build_xrnm.py --check minilab_renoise.xrnm

Dépend de mido + python-rtmidi (pip install mido python-rtmidi).
Ctrl-C pour annuler.
"""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET

# --- Plan : (libellé, action Renoise, mode, note_mode) ---------------------
# Actions toutes CONFIRMÉES depuis tes propres exports .xrnm.
# Pads 1-8 = navigation ; pads 9-16 = Mute des 8 tracks.
PAD_TASKS = [
    ("Pad 1  : Pattern précédent", "Navigation:Sequencer:Select Previous Sequence Pos [Trigger]", "Notes", "Trigger"),
    ("Pad 2  : Pattern suivant",   "Navigation:Sequencer:Select Next Sequence Pos [Trigger]",     "Notes", "Trigger"),
    ("Pad 3  : Track précédente",  "Navigation:Tracks:Select Previous Track [Trigger]",           "Notes", "Trigger"),
    ("Pad 4  : Track suivante",    "Navigation:Tracks:Select Next Track [Trigger]",               "Notes", "Trigger"),
    ("Pad 5  : DSP précédent",     "Navigation:Track DSPs:Select Previous Track DSP [Trigger]",   "Notes", "Trigger"),
    ("Pad 6  : DSP suivant",       "Navigation:Track DSPs:Select Next Track DSP [Trigger]",       "Notes", "Trigger"),
    ("Pad 7  : Vue éditeur pattern", "GUI:Middle Frame:Show Pattern Editor [Trigger]",            "Notes", "Trigger"),
    ("Pad 8  : Vue éditeur MIDI",  "GUI:Middle Frame:Show Instrument Midi Editor [Trigger]",      "Notes", "Trigger"),
    ("Pad 9  : Mute Track 1", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #01 [Toggle]", "Notes", "Value"),
    ("Pad 10 : Mute Track 2", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #02 [Toggle]", "Notes", "Value"),
    ("Pad 11 : Mute Track 3", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #03 [Toggle]", "Notes", "Value"),
    ("Pad 12 : Mute Track 4", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #04 [Toggle]", "Notes", "Value"),
    ("Pad 13 : Mute Track 5", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #05 [Toggle]", "Notes", "Value"),
    ("Pad 14 : Mute Track 6", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #06 [Toggle]", "Notes", "Value"),
    ("Pad 15 : Mute Track 7", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #07 [Toggle]", "Notes", "Value"),
    ("Pad 16 : Mute Track 8", "Track Muting:Mute/Unmute:Track XX [Toggle]:Track #08 [Toggle]", "Notes", "Value"),
]
# Encodeurs : déjà validés (Volume tracks 1-8, CC 21-28, canal 0/Ch1->affiché Ch2).
ENCODER_BLOCK = [
    (f"Track Levels:Volume:Track XX (Pre):Track #{i:02d} [Set]",
     "Controllers", "Trigger", 1, 20 + i) for i in range(1, 9)
]


def _mido():
    try:
        import mido
    except ImportError:
        sys.exit("mido manquant : pip install mido python-rtmidi")
    return mido


def _resolve(ports, wanted):
    if wanted in ports:
        return wanted
    m = [p for p in ports if wanted.lower() in p.lower()]
    if len(m) == 1:
        return m[0]
    sys.exit(f"Port {wanted!r} introuvable/ambigu. Ports : {ports}")


def _capture_one(inp, mido):
    """Bloque jusqu'au 1er note_on(vel>0) ou control_change ; renvoie
    (mapping_mode, channel0, number) ou None si l'utilisateur tape Entrée
    pour passer."""
    for msg in inp:
        if msg.type == "note_on" and msg.velocity > 0:
            return ("Notes", msg.channel, msg.note)
        if msg.type == "control_change":
            return ("Controllers", msg.channel, msg.control)
        # note_off / sysex / clock : ignorés


def _input(prompt):
    try:
        return input(prompt).strip().lower()
    except (EOFError, KeyboardInterrupt):
        print("\nAnnulé.")
        sys.exit(1)


def build(port_fragment: str, out_path: str) -> None:
    mido = _mido()
    target = _resolve(mido.get_input_names(), port_fragment)
    print(f"Port : {target!r}\n")
    print("Pour chaque ligne : appuie/tourne le contrôle voulu, puis")
    print("confirme. Collision et 'refaire' relancent la même ligne.\n")

    captured: list[tuple] = []           # (action, mode, note_mode, ch0, num)
    used: dict[tuple, str] = {}          # (ch0, kind, num) -> libellé

    i = 0
    with mido.open_input(target) as inp:
        while i < len(PAD_TASKS):
            label, action, mode, note_mode = PAD_TASKS[i]
            print(f"→ {label}")
            print("   (appuie/tourne le contrôle voulu…)")
            cap = _capture_one(inp, mido)
            kind = "cc" if cap[0] == "Controllers" else "note"
            key = (cap[1], kind, cap[2])
            disp_ch = cap[1] + 1
            print(f"   reçu : {kind.upper()} {cap[2]} (canal affiché {disp_ch})")

            if key in used:
                print(f"   ⚠  COLLISION avec « {used[key]} » — même contrôle !")
                if _input("   [Entrée]=refaire ce pad / s=garder quand même : ") != "s":
                    continue  # reprise : on redemande la même tâche

            ans = _input("   OK ? [Entrée]=oui / r=refaire / s=sauter : ")
            if ans == "r":
                continue
            if ans == "s":
                i += 1
                continue
            used[key] = label
            captured.append((action, mode, note_mode, cap[1], cap[2]))
            i += 1
            print()

    _write_xrnm(out_path, captured)
    print(f"\n✓ Écrit : {out_path}")
    report = validate(out_path)
    print(report)


def _write_xrnm(path: str, pad_caps: list[tuple]) -> None:
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<MidiActionMappingSet doc_version="0">',
             '  <ActionMappings>']

    def emit(action, mode, note_mode, ch0, num):
        ctrl = "Absolute 7 bit" if mode == "Controllers" else "Relative two's comp"
        lines.extend([
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
        ])

    for action, mode, nm, ch0, num in ENCODER_BLOCK_RESOLVED():
        emit(action, mode, nm, ch0, num)
    for action, mode, nm, ch0, num in pad_caps:
        emit(action, mode, nm, ch0, num)

    lines += ['  </ActionMappings>', '</MidiActionMappingSet>', '']
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def ENCODER_BLOCK_RESOLVED():
    # (action, mode, note_mode, channel0, cc)
    return [(a, m, nm, ch, cc) for (a, m, nm, ch, cc) in ENCODER_BLOCK]


def validate(path: str) -> str:
    """Revalide : XML bien formé + AUCUNE collision (canal+type+numéro)."""
    out = ["\n=== Validation ==="]
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        return f"\n✗ XML invalide : {e}"
    seen: dict[tuple, str] = {}
    n = 0
    for am in tree.findall(".//ActionMapping"):
        n += 1
        action = (am.findtext("Action") or "?").strip()
        mm = am.find(".//MidiMapping")
        mode = mm.findtext("MappingMode")
        ch = mm.findtext("Channel")
        num = mm.findtext("CCNumberOrNote")
        kind = "note" if mode == "Notes" else "cc"
        key = (ch, kind, num)
        if key in seen:
            out.append(f"✗ COLLISION {kind} {num} ch{ch} : "
                       f"« {action} » ET « {seen[key]} »")
        else:
            seen[key] = action
    collisions = [l for l in out if l.startswith("✗")]
    out.append(f"{n} mappings, {len(collisions)} collision(s).")
    out.append("✓ OK, aucun conflit." if not collisions
               else "✗ Corrige les collisions ci-dessus (relance la capture).")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", help="Fragment du port MIDI d'entrée")
    ap.add_argument("--out", default="minilab_renoise.xrnm")
    ap.add_argument("--check", help="Valider un .xrnm existant et quitter")
    args = ap.parse_args()
    if args.check:
        print(validate(args.check))
        return
    if not args.port:
        m = _mido()
        print("Ports :", m.get_input_names())
        print("Relance avec --port <fragment> --out fichier.xrnm")
        return
    build(args.port, args.out)


if __name__ == "__main__":
    main()
