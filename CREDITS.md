# Credits et sources

Ce projet est construit sur du reverse-engineering du protocole SysEx
de la Behringer TD-3-MO, combiné avec les travaux publics suivants.

## Documentation et reverse-engineering du format

### 303 Pattern Tool — Brad Isbell / AudioPump, Inc.

- Site : https://303patterns.com/
- Page format : https://303patterns.com/td3-midi.html
- Code : application web closed-source, JS bundle public et lisible

Source principale de l'analyse du format SysEx TD-3 (opcodes 0x77 / 0x78
pour les patterns, opcodes 0x0E-0x1C / 0x75 / 0x76 pour la config). Le
modèle de données utilisé dans `src/td3/pattern.py` et `src/td3/config.py`
suit les conventions trouvées dans leur code JS désassemblé.

### beholder-d/td3-pattern — Rust CLI

- Repo : https://github.com/beholder-d/td3-pattern
- Licence : MIT

Référence cross-check pour le HOLD mask (bit clear = held / tied), la
disposition packed-vs-step-indexed des pitches, et la quirk Tie/Rest du
firmware. Mentionnée dans `src/td3/pattern.py`.

### echolevel/Acid-Injector — JavaScript MIDI → .seq

- Repo : https://github.com/echolevel/Acid-Injector
- Licence : MIT

Utilisé comme source pour le magic header du format `.seq` (`23 98 54 76`)
et l'analyse de la zone "Tie/Rest map" (nibble swap [1,0,3,2]). Voir
`docs/td3-mo-fr.md` pour la comparaison .sqs vs .seq.

### claziss/CraveSeq — Parser C pour TD-3 et Crave

- Repo : https://github.com/claziss/CraveSeq
- Licence : GPLv3

Référence pour la documentation ASCII des layouts TD-3 et Behringer Crave
dans son `src/parser.c`. Pas de code copié, mais inspiration pour la
documentation interne.

### Behringer TD-3-MO Quick Start Guide

- Fichier : `QSG_BE_0718-ABX_TD-3-MO_WW.pdf` (multi-langue) +
  `QSG_BE_0718-ABX_TD-3-MO_CN.pdf` (chinois)
- © Behringer / Music Tribe Global Brands Ltd

Documentation officielle Behringer fournie dans le repo pour référence
(procédure SYNC/CLOCK page 40, MIDI Implementation Chart page 64, etc.).
Le résumé français exploitable est dans `docs/td3-mo-fr.md`.

### Microsoft Windows MIDI Services Console

- Repo : https://github.com/microsoft/MIDI

Utilisé comme outil de capture / sniff pendant le développement (validation
byte-à-byte du SysEx émis par Synthtribe). Pas de dépendance code.

## Dépendances logicielles directes

### Python (lib `td3`)

Déclarées dans `pyproject.toml` :

- **click** ≥ 8.0 — CLI framework. BSD-3-Clause.
- **PyYAML** ≥ 6.0 — Parser YAML. MIT.
- **mido** ≥ 1.3 (optionnel, extra `[midi]`) — Abstraction MIDI portable.
  MIT.
- **python-rtmidi** ≥ 1.5 (optionnel, extra `[midi]`) — Bindings rtmidi
  pour mido. MIT.
- **pytest** ≥ 7 (dev) — Tests.

### Renoise Tool (`com.timox.td3-renoise.xrnx`)

Utilise uniquement l'API scripting Renoise officielle (Lua 5.1 + ViewBuilder
+ Renoise.Midi). Aucune dépendance Lua externe.

API documentée : https://github.com/renoise/xrnx

## Outils tiers mentionnés (sans dépendance)

- **loopMIDI** — Tobias Erichsen, freeware
  (https://www.tobias-erichsen.de/software/loopmidi.html). Port MIDI
  virtuel Windows pour sniff. Remplacé par les Default App Loopback (A/B)
  du nouveau Windows MIDI Services.
- **MIDI-OX** — Jamie O'Connell, freeware (https://www.midiox.com/).
  Monitor MIDI GUI Windows.
- **Synthtribe** — Behringer / Music Tribe, freeware. Logiciel officiel
  d'édition pour la TD-3.

## Données binaires incluses

- `td3dump.sqs` (7972 octets) : dump factory de la TD-3-MO firmware 2.0.1.
  Contient les 64 patterns d'usine de l'instrument. Utilisé comme base de
  tests de round-trip byte-exact.
- `QSG_BE_0718-ABX_TD-3-MO_*.pdf` : documentation officielle Behringer.

Si ce dépôt devient public, considérer si ces fichiers doivent rester
versionnés ou être déplacés dans une release attachée séparément.

## Travaux dérivés

Si vous utilisez ou modifiez ce code, merci de citer ce dépôt et de
préserver les attributions ci-dessus. Voir [`LICENSE`](LICENSE)
(PolyForm Noncommercial 1.0.0) pour les termes exacts : copie,
modification et distribution autorisées **sans usage commercial**.
