# td333 — outils Behringer TD-3 (-MO)

Trois outils pour composer, enregistrer et piloter la **Behringer TD-3-MO**
(et la TD-3 standard sans le MO) depuis un ordinateur :

1. **Lib Python `td3`** : décodeur/encodeur des patterns (.sqs, .syx, YAML),
   CLI pour manipuler les dumps et envoyer des SysEx.
2. **Tool Renoise `.xrnx`** : éditeur de pattern grille style 303 dans
   Renoise, avec preview MIDI, sync au tempo Renoise, bounce vers Sample
   Recorder, Read/Write des slots de la TD-3.
3. **`docs/td3-mo-fr.md`** : aide-mémoire FR du QSG officiel TD-3-MO,
   notamment la procédure pour passer la TD-3 en clock source MIDI USB
   (cachée dans la doc Behringer).

Branche de dev : `claude/td3-midi-patterns-AXciF`. Le `main` est conservé
pour les dumps de référence (`td3dump.sqs`, `QSG_BE_…pdf`).

---

## Lib Python + CLI `td3`

### Installation

Python ≥ 3.10. Dans le dossier du repo cloné :

```bash
# Lib seule (manipulation .sqs / .syx / YAML, pas de MIDI live)
pip install -e .

# Avec MIDI live (nécessite mido + python-rtmidi)
pip install -e ".[midi]"
```

→ crée la commande `td3` dans le PATH. Si elle n'apparaît pas (Windows
notamment), lancer à la place : `python -m td3.cli ...`

### Commandes (résumé)

```bash
td3 ports                                 # liste les ports MIDI in/out
td3 unpack td3dump.sqs --out patterns/    # .sqs → 64 YAML lisibles
td3 pack patterns/ --out custom.sqs       # YAML → .sqs (compat Synthtribe)
td3 yaml-to-syx pattern.yml               # YAML → .syx
td3 syx-to-yaml dump.syx                  # .syx → YAML
td3 send pattern.yml --port "TD-3-MO"     # envoi SysEx live vers un slot
td3 send-all patterns/ --port "TD-3"      # envoi de la banque entière
td3 monitor --port "loopback" --forward-to "TD-3-MO"  # sniffer passthrough
td3 sniff   --port "TD-3-MO" --out cc.json     # capture interactive
td3 probe   --port "TD-3-MO"              # envoi CC 0..127 + écoute oreille
```

→ **Documentation détaillée + exemples + workflows** : voir
[`docs/cli.md`](docs/cli.md).

### Format YAML d'un pattern

Convention TB-303 : 4 groupes (I, II, III, IV), 16 patterns par groupe
(1A..8A, 1B..8B). Storage pitch = MIDI − 12, clampée à C1..C4.

```yaml
group: I              # I, II, III, IV (ou 0..3)
pattern: "1A"         # 1A..8A (= 0..7), 1B..8B (= 8..15)
triplet: false
step_count: 16
seq:
  - "F#3 slide"       # note + flags : accent, slide, tie, rest
  - "E3 slide"
  - "D3 rest"         # silence avec pitch fantôme préservé pour round-trip
  - "B2"
  - "-"               # silence "vide" (= rest avec pitch placeholder C2)
  # ... jusqu'à 16 entrées
```

Round-trip byte-exact garanti sur les 64 patterns du dump usine
(`td3dump.sqs`).

---

## Tool Renoise `com.timox.td3-renoise.xrnx`

### Installation

**Pré-requis** : **Renoise ≥ 3.5.4** (= API scripting **6.2** ; nécessaire
pour piloter le Sample Recorder via `start_sample_recording`). Les versions
plus anciennes ne supportent pas le bouton **⏺ Bounce**.

```bash
cd renoise
zip -r td3-renoise.xrnx com.timox.td3-renoise.xrnx
```

Glisser `td3-renoise.xrnx` sur la fenêtre Renoise (ou Tools → Browse for
tools). Lancer via **Tools → TD-3 Pattern Editor** ou raccourci configurable.

### Setup TD-3 minimal pour tester

| Réglage TD-3 | Valeur | Comment |
|---|---|---|
| Clock source | **MIDI USB** | Façade : Function + (BACK + WRITE/NEXT) + Selector **3**. Détails dans `docs/td3-mo-fr.md`. |
| MIDI input channel | 1 (défaut) | Modifiable via SysEx, voir bouton dans le tool |
| Accent velocity threshold | ≤ 100 | 127 par défaut → presque rien n'est accentué. Le tool propose un slider qui pousse via SysEx. |
| MODE | Pattern Play | Pour que MIDI Start lance le séquenceur interne |

### Workflow Bounce vers Renoise

1. Câbler audio TD-3 OUT → entrée audio Renoise (Edit → Preferences → Audio
   Devices → Input)
2. **Mode A** (recommandé pour vrai son 303) :
   - Composer dans la grille du tool
   - **Write to TD-3** dans le slot voulu (par ex. IV-1A)
   - **Sur la façade TD-3** : sélectionner manuellement ce slot
     (Behringer/Synthtribe n'expose pas la sélection programmatique)
   - Renoise Play + ⏺ Bounce dans le tool → Sample Recorder armé
   - Au prochain top de pattern Renoise, MIDI Start lance le séquenceur
     TD-3 + recording démarre, en phase
   - Stop → fin de prise, sample créé
3. **Mode B** (preview rapide) :
   - Cliquer ▶ Preview ou ▶ Sync : envoie les notes via MIDI temps réel
   - Pas de slide / accent natif TD-3 (limite firmware Behringer en MIDI in)

### Multiplicateur de tempo

Popup `step =` dans la barre Preview :
- ×0.25 → step = 1/4 (lent, drone)
- ×0.5 → 1/8
- ×1 → 1/16 (défaut)
- ×2 → 1/32 (boucle 2× plus rapide, idéale pour 8 répétitions dans un
  pattern Renoise de 128 lignes)
- ×4 → 1/64

Toujours synchro avec le BPM Renoise.

---

## Sniffer Synthtribe (Windows)

Pour découvrir d'éventuels SysEx non documentés que Synthtribe enverrait :

1. Installer **loopMIDI**
   (https://www.tobias-erichsen.de/software/loopmidi.html), créer un
   port virtuel "TD-3-Sniff".
2. Lancer notre passthrough :
   ```bash
   td3 monitor --port "TD-3-Sniff" --forward-to "TD-3 MIDI 1"
   ```
3. Dans Synthtribe : changer le MIDI Out vers "TD-3-Sniff" au lieu de la
   TD-3 directe.
4. Tout ce que Synthtribe envoie est affiché en hex avec timestamp, ET
   relayé à la TD-3 normalement.

Alternative GUI sans Python : **MIDI-OX** (https://www.midiox.com/),
même routage.

---

## Travaux confirmés

- ✅ Round-trip `.sqs` byte-exact (64 patterns d'usine TD-3-MO 2.0.1)
- ✅ Round-trip YAML byte-exact via le pipeline complet
- ✅ SysEx 0x77 / 0x78 (Read/Write pattern) testé sur device
- ✅ SysEx 0x75 / 0x76 (Read config) + 0x1B (Set Clock) + 0x1C (Set
  Accent Threshold) testés sur device
- ✅ Preview MIDI live + sync BPM Renoise + step rate multiplicateur
- ✅ ⏺ Bounce → Sample Recorder via API Renoise 6.2 (`start_sample_recording`)

## Limites connues

- ❌ Sélection programmatique du slot actif sur la TD-3 : aucun opcode
  documenté **et Synthtribe ne le fait pas non plus** → manuel obligatoire
  sur la façade
- ❌ CC sound design (Resonance, Env Mod, Decay, Accent intensity) :
  Behringer n'expose que CC 74 (Cutoff). Tout le reste est sur les
  potards façade.
- ❌ Slide / accent en MIDI temps réel : approximations seulement (pas
  de slide audible via overlap de notes selon les firmwares). Pour le
  vrai comportement TB-303, passer par le séquenceur interne (Mode A).
- ❌ Format des "tracks" (chaînes de patterns) non analysé.

## Licence

Voir headers individuels. Le dépôt contient un dump factory de la TD-3-MO
(`td3dump.sqs`) et un PDF QSG Behringer fournis par l'utilisateur — usage
personnel.
