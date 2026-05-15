# Arturia MiniLab MkII → Renoise

Mapping clavier/contrôleur **Arturia MiniLab MkII** pour piloter Renoise :
navigation **pattern ↔ pattern**, **track ↔ track**, **DSP ↔ DSP**, et
volume des 8 premières pistes.

| Fichier | Rôle |
|---|---|
| `minilab_renoise.xrnm` | Mapping MIDI à charger dans Renoise |
| `layout.png` | Plan visuel (qui fait quoi sur le clavier) |
| `README.md` | Ce document |
| `midi_dump.py` | Script pour identifier ce qu'envoie chaque contrôle |
| `build_xrnm.py` | Construction assistée + validée du `.xrnm` (zéro saisie manuelle) |

## Construire le mapping sans se planter

`build_xrnm.py` supprime la transcription manuelle : il te demande
fonction par fonction d'actionner le bon contrôle, **capture le MIDI
réel**, te fait **confirmer**, détecte les **collisions** et **reprend**
la ligne en cas d'erreur, puis écrit le `.xrnm` et le **revalide**.

```bash
pip install mido python-rtmidi
python3 controllers/minilab-mkii/build_xrnm.py --port minilab --out controllers/minilab-mkii/minilab_renoise.xrnm
# revalider un fichier existant :
python3 controllers/minilab-mkii/build_xrnm.py --check controllers/minilab-mkii/minilab_renoise.xrnm
```

Cycle par ligne : actionne le contrôle → message capturé → `Entrée`=ok /
`r`=refaire / `s`=sauter. Toute collision (même canal+note/CC déjà pris)
force la reprise. En fin de course, rapport de validation (XML +
absence de conflit).

## Identifier les contrôles (pads 9-16, etc.)

Plutôt que le *Learn Mode* pad par pad, utilise le dumper :

```bash
pip install mido python-rtmidi      # ou : pip install -e ".[midi]"
python3 controllers/minilab-mkii/midi_dump.py                 # liste les ports
python3 controllers/minilab-mkii/midi_dump.py --port minilab  # écoute
```

Appuie/tourne chaque pad/knob : chaque message est décodé avec le
canal, la note/CC **et la ligne `.xrnm` correspondante** déjà formatée.
Le SysEx du bouton de banque s'affiche tagué « Arturia interne —
ignorer ». Copie-colle la sortie et envoie-la pour étendre le mapping.

## Installation

1. **Arturia MIDI Control Center** : charge un template *User/DAW*, pads
   et knobs en **CC/Notes fixes**, puis *Store To* le MiniLab. Ferme
   ensuite MCC (il verrouille le port USB, sinon Renoise ne reçoit rien).
2. **Renoise** → `Preferences → MIDI` : active le MiniLab dans un slot
   *In Device*.
3. Ouvre la fenêtre **MIDI Mapping** → bouton **Load** →
   `minilab_renoise.xrnm`.

## Plan visuel

![Plan de mapping MiniLab MkII](layout.png)

```mermaid
flowchart TB
  subgraph ENC["Encodeurs rangee haute - Ch2, CC 21-28 (absolu)"]
    direction LR
    E1["1 - CC21<br/>Vol Track 1"]
    E2["2 - CC22<br/>Vol Track 2"]
    E3["3 - CC23<br/>Vol Track 3"]
    E4["4 - CC24<br/>Vol Track 4"]
    E5["5 - CC25<br/>Vol Track 5"]
    E6["6 - CC26<br/>Vol Track 6"]
    E7["7 - CC27<br/>Vol Track 7"]
    E8["8 - CC28<br/>Vol Track 8"]
  end
  subgraph PADS["Pads - Ch10, notes 36-43 (Trigger)"]
    direction TB
    subgraph PR1["Rangee haute"]
      direction LR
      P1["Pad 1 - n36<br/>&#9664; Pattern"]
      P2["Pad 2 - n37<br/>Pattern &#9654;"]
      P3["Pad 3 - n38<br/>&#9664; Track"]
      P4["Pad 4 - n39<br/>Track &#9654;"]
    end
    subgraph PR2["Rangee basse"]
      direction LR
      P5["Pad 5 - n40<br/>&#9664; DSP"]
      P6["Pad 6 - n41<br/>DSP &#9654;"]
      P7["Pad 7 - n42<br/>Vue Pattern"]
      P8["Pad 8 - n43<br/>Vue MIDI"]
    end
  end
  ENC ~~~ PADS
```

## Tableau de correspondance

### Encodeurs (rangée haute) — MIDI canal 2, CC absolu

| Encodeur | CC | Fonction Renoise |
|---|---|---|
| 1 | 21 | Volume Track 1 |
| 2 | 22 | Volume Track 2 |
| 3 | 23 | Volume Track 3 |
| 4 | 24 | Volume Track 4 |
| 5 | 25 | Volume Track 5 |
| 6 | 26 | Volume Track 6 |
| 7 | 27 | Volume Track 7 |
| 8 | 28 | Volume Track 8 |

### Pads — MIDI canal 10, Note (Trigger)

| Pad | Note | Fonction Renoise | Action interne |
|---|---|---|---|
| 1 | 36 | ◀ Pattern précédent | `Navigation:Sequencer:Select Previous Sequence Pos` |
| 2 | 37 | Pattern suivant ▶ | `Navigation:Sequencer:Select Next Sequence Pos` |
| 3 | 38 | ◀ Track précédente | `Navigation:Tracks:Select Previous Track` |
| 4 | 39 | Track suivante ▶ | `Navigation:Tracks:Select Next Track` |
| 5 | 40 | ◀ DSP précédent | `Navigation:Track DSPs:Select Previous Track DSP` |
| 6 | 41 | DSP suivant ▶ | `Navigation:Track DSPs:Select Next Track DSP` |
| 7 | 42 | Vue éditeur de pattern | `GUI:Middle Frame:Show Pattern Editor` |
| 8 | 43 | Vue éditeur MIDI | `GUI:Middle Frame:Show Instrument Midi Editor` |

## Notes importantes

- **Canaux** : dans le fichier `.xrnm`, `<Channel>` est *0-based* →
  `1` s'affiche **Ch2** dans Renoise, `9` s'affiche **Ch10**. Les
  encodeurs sont sur le canal 2, les pads sur le canal 10 (valeurs
  relevées sur tes propres captures, donc cohérentes avec ton MiniLab).
- **Si un pad ne réagit pas** : sa note réelle (preset MCC) diffère de
  36-43. En *Learn Mode* dans la fenêtre MIDI Mapping, tape le pad : le
  numéro reçu s'affiche → corrige le `<CCNumberOrNote>` correspondant.
- **« Pattern précédent/suivant »** = avancer/reculer dans la **séquence
  du morceau** (l'arrangement). Pour changer *quel* pattern occupe le
  slot courant, ce sont d'autres actions
  (`Navigation:Sequencer:Increase/Decrease Current Pattern`).
- Une action `[Trigger]` se déclenche au coup de pad ; mets les pads en
  **Gate** ou **Trigger** côté MCC (pas Toggle) pour ces fonctions.

## Extensions possibles

- 2ᵉ banque d'encodeurs → volume tracks 9-16, ou paramètres du **DSP
  sélectionné** (clic droit sur un paramètre d'effet → *Set MIDI
  Mapping* → tourne le knob).
- 2ᵉ banque de pads → Mute/Solo des tracks, transport (Play/Stop),
  Loop, etc.

Donne les numéros CC/notes de ta 2ᵉ banque (preset MCC) et on étend le
fichier.
