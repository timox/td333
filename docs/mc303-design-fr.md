# Roland MC-303 — Document de conception du tool Renoise

Conception d'un tool Renoise `.xrnx` pour la **Roland MC-303 Groovebox**
(1996), calqué sur l'outil TD-3 existant
(`renoise/com.timox.td3-renoise.xrnx/`). **Aucun code n'est encore
écrit** : ce document fixe le périmètre, l'architecture et les
arbitrages à valider avant implémentation.

> Statut : proposition. Les points marqués ⚠️ doivent être vérifiés sur
> hardware (l'implémentation MIDI de la MC-303 est partielle et mal
> documentée par Roland).

---

## 1. Vue d'ensemble MC-303

- Groovebox multitimbrale **8 parties** : 7 parties mélodiques + 1
  partie **Rhythm** (batterie).
- ~448 tones PCM (banques GM-like Roland) + kits de batterie.
- Séquenceur de patterns interne + arpégiateur + filtre/résonance temps
  réel sur potards façade (le « son MC-303 »).
- Connectique : MIDI IN/OUT/THRU DIN, audio. **Pas d'USB**.
- Synchronisable à l'horloge MIDI (esclave **ou** maître).

## 2. Capacités MIDI — la différence majeure avec la TD-3

La TD-3 a un atout central que la MC-303 **n'a pas** : le dump SysEx de
patterns (opcodes `0x77`/`0x78`, lecture/écriture des slots mémoire).

| Capacité | TD-3 | MC-303 |
|---|---|---|
| Note On/Off, vélocité | ✅ | ✅ |
| Program Change / Bank Select | — | ✅ (sélection tones par partie) |
| Multitimbral | ❌ (mono) | ✅ (8 parties) |
| CC sound design | ❌ (CC74 seul) | ✅ (set GS : cutoff/reso/env…) |
| NRPN GS | ❌ | ✅ (sous-ensemble) |
| Sync horloge MIDI | ✅ | ✅ |
| **Dump SysEx pattern/song** | ✅ | ❌ **impossible** |

**Conséquence d'architecture :** l'équivalent MC-303 du *TD-3 Pattern
Editor* (lecture/écriture mémoire) **n'existe pas** — la MC-303 ne
transfère ni patterns ni songs en SysEx (limitation corrigée seulement
sur MC-505/D2). Le tool MC-303 est donc bâti **uniquement** sur le
modèle *MIDI-live* : la MC-303 = module de son multitimbral, Renoise =
séquenceur. C'est exactement le moteur du dialogue *TD-3 MIDI-live
(32 pas + FX)* (`main.lua:1289-1832`), étendu au multipart.

### 2.1 Mapping parties ↔ canaux MIDI

Les canaux de réception sont configurables par partie sur la façade.
Convention par défaut proposée (⚠️ à confirmer sur device) :

| Partie | Canal MIDI déf. | Rôle |
|---|---|---|
| Rhythm (R) | 10 | batterie (note-map type GM/Roland) |
| Partie 1 | 1 | mélodique |
| … | … | … |
| Partie 7 | 7 | mélodique |

Le tool exposera le canal par partie en paramètre (pas de découverte
automatique possible).

### 2.2 Control Change reçus (set GS utile)

| CC | Fonction |
|---|---|
| 0 / 32 | Bank Select MSB/LSB |
| 1 | Modulation |
| 5 / 65 | Portamento time / on-off |
| 7 / 11 | Volume / Expression |
| 10 | Pan |
| 64 | Hold 1 |
| 71 | Resonance (TVF) |
| 72 / 73 | Release / Attack time |
| 74 | Cutoff (TVF) — le potard filtre |
| 75 | Decay time |
| 91 / 93 | Reverb send / Chorus(Delay) send |
| 120/121/123 | All sound off / Reset controllers / All notes off |

### 2.3 NRPN GS (tweak temps réel — sous-ensemble ⚠️)

Adressage GS standard `NRPN MSB / LSB → data`. Sous-ensemble
typiquement supporté par la MC-303 :

| NRPN (hex) | Paramètre |
|---|---|
| `01 08 / 09 / 0A` | Vibrato rate / depth / delay |
| `01 20` | TVF cutoff |
| `01 21` | TVF resonance |
| `01 63 / 64 / 66` | Env attack / decay / release |
| `18 nn` | Drum *nn* : pitch coarse |
| `1A nn` | Drum *nn* : niveau (TVA) |
| `1C nn` | Drum *nn* : pan |
| `1D nn` / `1E nn` | Drum *nn* : reverb / chorus send |

(`nn` = numéro de note de l'instrument de batterie.)

### 2.4 SysEx

GS Reset et paramètres GS par partie (Roland, model ID `0x42`,
device `0x10`) sont acceptés pour le **son** uniquement. Aucun SysEx
pattern/song. Le tool n'enverra qu'un **GS Reset optionnel** au start
(`F0 41 10 42 12 40 00 7F 00 41 F7`).

---

## 3. Architecture du tool `.xrnx`

Nouveau dossier `renoise/com.timox.mc303-renoise.xrnx/`, structure
identique au TD-3 :

```
com.timox.mc303-renoise.xrnx/
  manifest.xml      # Id com.timox.mc303-renoise, ApiVersion 6.2
  mc303.lua         # couche protocole (pas de codec SysEx pattern)
  main.lua          # dialogues UI
```

### 3.1 `mc303.lua` — couche protocole

Rôle analogue à `td3.lua` mais **sans codec de pattern SysEx**. Contenu :

- Tables : libellés tones/banques par défaut, note-map batterie (R),
  libellés parties.
- `part_channel(part)` / configuration canaux.
- Encodeurs MIDI : `program_change`, `bank_select`,
  `nrpn(ch, msb, lsb, value)` (séquence CC 99/98/6/38), helpers CC
  nommés (cutoff, reso, env, sends).
- `gs_reset()` → message SysEx.
- Réutilise les helpers génériques du TD-3 (`bytes_to_hex`,
  sérialisation YAML de pattern adaptée multipart).

### 3.2 `main.lua` — dialogues UI

Deux dialogues (Renoise n'a pas d'onglets natifs, même contrainte que
le TD-3 — cf. README) :

#### Dialogue A — **MC-303 Multipart Live** (séquenceur)

Moteur **calqué sur le TD-3 live 32 pas + FX** (`lp_*`,
`main.lua:1351-1535`), étendu :

- Sélecteur de **partie active** (R + 1..7) ; une grille de pas par
  partie, jusqu'à 32 pas.
- Par pas : note (ou note-map batterie pour R), vélocité/accent,
  gate/longueur, microtiming, ratchet — mêmes primitives que le TD-3
  live.
- **FX par pas** étendu aux NRPN/CC GS (cutoff CC74, resonance CC71,
  env, sends) en plus du cutoff TD-3.
- Program Change / Bank Select par partie (choix du tone).
- Preview à horloge fine + sync BPM Renoise (réutilise
  `preview_*` / `lp_schedule`, `main.lua:490-601`).
- **Export → pistes Renoise** : une piste par partie active
  (adaptation de `lp_export_to_track`, `main.lua:1481-1535`).
- GS Reset optionnel à l'init.

#### Dialogue B — **MC-303 Tweak Panel** (sound design live)

- Faders par partie : cutoff, resonance, attack/decay/release, LFO,
  reverb/delay send (via NRPN GS ou CC selon §2.2/2.3).
- Section batterie : pitch/niveau/pan/send par instrument (`18/1A/1C…`).
- Capture des mouvements → colonnes d'effet / automation Renoise
  (même principe que la capture FX du TD-3 live).

### 3.3 Entrées de menu

```
Main Menu:Tools:MC-303 Multipart Live...
Main Menu:Tools:MC-303 Tweak Panel...
Pattern Editor:MC-303 Multipart Live...
+ keybindings Global:Tools:*
```

---

## 4. Limites connues (à documenter dans le README)

- ❌ Pas de lecture/écriture mémoire MC-303 (aucun SysEx pattern/song)
  → pas d'éditeur de slots, contrairement au TD-3.
- ❌ Pas de sélection programmatique du pattern interne MC-303.
- ⚠️ Sous-ensemble exact CC/NRPN supporté : à valider à l'oreille sur
  device (Roland ne publie pas la liste précise pour la MC-303).
- ⚠️ Mapping parties↔canaux par défaut : à confirmer sur device.
- ❌ Slide/accent TB-303 : non pertinent (MC-303 ≠ synthé mono) ;
  l'accent = vélocité élevée.

## 5. Roadmap d'implémentation proposée

1. Squelette : `manifest.xml` + `mc303.lua` (tables, encodeurs MIDI,
   NRPN, GS reset) — testable hors Renoise via un harness simple.
2. Dialogue A *Multipart Live* : portage du moteur `lp_*` TD-3 →
   multipart + Program Change + export multi-pistes.
3. Dialogue B *Tweak Panel* : faders NRPN/CC + capture automation.
4. Validation hardware : confirmer §2.1/2.3/2.4, ajuster les tables.
5. Doc : section MC-303 dans `README.md` + entrée CLI si pertinent.

---

*Référence code TD-3 : moteur live `main.lua:1289-1832`, scheduler
`main.lua:1351-1535`, preview `main.lua:490-601`, codec `td3.lua`.*
