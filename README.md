# td333 — outils Behringer TD-3 (-MO)

Trois outils pour composer, enregistrer et piloter la **Behringer TD-3-MO**
(et la TD-3 standard sans le MO) depuis un ordinateur :

1. **Lib Python `td3`** : décodeur/encodeur des patterns
   (`.sqs`, `.seq`, `.syx`, YAML), CLI pour manipuler les dumps, envoyer
   des SysEx, sniffer Synthtribe. Format humain (YAML), batch, scripting.
2. **Tool Renoise `.xrnx`** : **deux éditeurs distincts** (Renoise n'ayant
   pas d'onglets natifs) —
   - **TD-3 Pattern Editor** (Hardware) : grille 16 pas style 303,
     Read/Write des slots TD-3 en SysEx, bibliothèque locale
     `.syx/.seq/.yml`, preview MIDI, bounce Sample Recorder.
   - **TD-3 MIDI-live (32 pas + FX)** : la TD-3 n'est qu'un module de
     son (aucune écriture mémoire), jusqu'à 32 pas, FX par pas
     (ratchet / cutoff CC74 / microtiming / gate), preview à horloge
     fine, export vers une piste Renoise.
3. **`docs/td3-mo-fr.md`** : aide-mémoire FR du QSG officiel TD-3-MO,
   notamment la procédure pour passer la TD-3 en clock source MIDI USB
   (cachée dans la doc Behringer).

Branche de dev : `claude/td3-midi-patterns-AXciF`.

> Le dump factory `td3dump.sqs` et les PDF QSG Behringer ne sont **pas**
> distribués (contenu propriétaire). La lib et la suite de tests
> fonctionnent sans : un banc synthétique de 64 patterns sert de
> substitut quand le dump est absent (voir `tests/`).

---

## Lib Python + CLI `td3`

### Installation

Python ≥ 3.10. Dans le dossier du repo cloné :

```bash
# Lib seule (manipulation .sqs / .seq / .syx / YAML, pas de MIDI live)
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
td3 seq-to-yaml IVA.seq --slot IV-1A      # .seq (Synthtribe) → YAML
td3 send pattern.yml --port "TD-3-MO"     # envoi SysEx live vers un slot
td3 send-seq IVA.seq --port "TD-3" --slot IV-1A   # .seq → slot direct
td3 send-track track.yml --port "TD-3"    # flashe une chaîne de patterns
td3 send-all patterns/ --port "TD-3"      # envoi de la banque entière
td3 monitor --port "loopback" --forward-to "TD-3-MO"  # sniffer passthrough
td3 sniff   --port "TD-3-MO" --out cc.json     # capture interactive
td3 probe   --port "TD-3-MO"              # envoi CC 0..127 + écoute oreille
```

→ **Documentation détaillée + exemples + workflows** : voir
[`docs/cli.md`](docs/cli.md).

### Formats de fichier

- **`.sqs`** : banque complète 64 patterns (export Synthtribe « Backup »).
- **`.seq`** : pattern unique (export Synthtribe « Export »). Le slot
  cible n'est pas dans le fichier → passé en argument (`--slot`) ou
  déduit du nom.
- **`.syx`** : message SysEx brut `F0…F7` (opcode 0x78) d'un pattern.
- **YAML** : format humain éditable (ci-dessous).

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

Round-trip byte-exact garanti (vérifié sur le dump usine TD-3-MO 2.0.1
quand présent, sinon sur le banc synthétique de la suite de tests).

### Track (chaîne de patterns)

`td3 send-track track.yml --port …` écrit chaque pattern dans un slot
consécutif d'un groupe puis **imprime l'ordre de chaînage à reproduire
manuellement** en mode TRACK WRITE (le chaînage lui-même n'a aucun
opcode SysEx connu).

```yaml
name: "Mon set acid"
group: I                                  # I..IV
patterns:
  - patterns/library/01_acid_classic.yml
  - patterns/library/03_octave_jump.yml
  - patterns/library/02_rolling_16th.yml
```

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
tools). Deux entrées apparaissent dans **Tools** :

- **TD-3 Pattern Editor** — éditeur Hardware
- **TD-3 MIDI-live (32 pas + FX)** — éditeur MIDI-live

> À la fermeture de l'une ou l'autre fenêtre, toutes les notes sont
> coupées automatiquement (panic + All-Notes-Off) : une note tenue par
> un slide ne reste jamais bloquée.

### Éditeur Hardware (TD-3 Pattern Editor)

Grille 303 : 4 lignes OCT (1..4), 12 lignes PITCH, lignes SLIDE et
ACCENT, sur 16 pas. Permet de :

- **Read TD-3 / Write to TD-3** : lit/écrit un slot (groupe I..IV /
  pattern 1A..8B) en SysEx (clock source = MIDI USB obligatoire).
- **Check TD-3** : diagnostic firmware / canal / clock source / seuil
  d'accent, avec écriture SysEx du clock source (0x1B) et du seuil
  d'accent (0x1C) depuis la toolbar.
- **Cutoff (CC 74)** : slider filtre live (seul CC sound-design exposé).
- **Bibliothèque** (panneau unifié) : un **dossier dédié** regroupe vos
  `.syx/.seq/.yml/.yaml`, listés dans un popup → sélection directe.
  Bouton *Fichier…* = un seul browser multi-format. Le **format est
  auto-détecté sur le contenu** (magic `.seq` → trame SysEx 0x78 →
  sinon YAML), donc l'extension/les filtres OS importent peu. À
  l'enregistrement, un popup `syx/seq/yml` choisit le format.
- **Transpose** : ±demi-ton / ±octave sur tout le pattern.
- **Preview / Sync / Bounce** : preview MIDI temps réel, synchro au
  prochain top de pattern Renoise, capture via Sample Recorder.

### Éditeur MIDI-live (32 pas + FX)

La TD-3 n'est qu'un **module de son** : **aucune écriture mémoire**, on
dépasse les limites hardware.

- **Jusqu'à 32 pas** (popup 16/32, défaut 32). Les pas hors longueur
  active sont grisés.
- **Lanes FX visibles** (une rangée par effet, 32 cellules) :
  - **RATCHET** : re-déclenchements 1..8 dans le pas.
  - **CUTOFF** : valeur CC 74 envoyée avant la note (−1 = off).
  - **DELAY** : microtiming ±60 ms (groove/shuffle).
  - **GATE** : longueur de note % (100 = tenu/legato).
  Vert = pas porteur de l'effet, bleu = pas sélectionné. Clic =
  sélectionne le pas ; la valeur précise s'édite dans l'inspecteur.
- **Preview à horloge fine** : timer haute résolution + file
  d'évènements datés, honore ratchet/cutoff/delay/gate + le legato des
  slides. Sync BPM Renoise ou `step ms` libre, loop.
- **→ Piste Renoise** : écrit `length` lignes dans la piste/pattern
  sélectionnés — note, volume = accent, **une colonne d'effet par
  effet** (col 1 = slide `0G`, col 2 = ratchet `0R`), microtiming dans
  la colonne *delay* native. L'édition fine au-delà des limites TD-3 se
  fait ensuite **nativement dans Renoise** (zéro réimplémentation).

### Setup TD-3 minimal pour tester

| Réglage TD-3 | Valeur | Comment |
|---|---|---|
| Clock source | **MIDI USB** | Façade : Function + (BACK + WRITE/NEXT) + Selector **3**. Détails dans `docs/td3-mo-fr.md`. |
| MIDI input channel | 1 (défaut) | Modifiable via SysEx, voir bouton dans le tool |
| Accent velocity threshold | ≤ 100 | 127 par défaut → presque rien n'est accentué. Le tool propose un slider qui pousse via SysEx. |
| MODE | Pattern Play | Pour que MIDI Start lance le séquenceur interne |

> **Important** : désactiver « MIDI Clock Master Output » vers le port
> TD-3 côté Renoise (Edit → Preferences → MIDI). Sinon Renoise envoie
> MIDI Start/Clock et le séquenceur interne TD-3 se lance en parallèle
> du preview. Le tool **n'envoie volontairement plus** de MIDI Stop
> (0xFC) : en clock MIDI USB cela mettait la TD-3 en « stopped » et lui
> faisait ignorer notes + CC (régression cutoff/slide).

### Workflow Bounce vers Renoise (éditeur Hardware)

1. Câbler audio TD-3 OUT → entrée audio Renoise (Edit → Preferences →
   Audio Devices → Input).
2. **Mode A** (vrai son 303, séquenceur interne) :
   - Composer dans la grille, **Write to TD-3** dans le slot voulu.
   - **Sur la façade TD-3** : sélectionner manuellement ce slot
     (aucune sélection programmatique — ni opcode connu, ni Synthtribe).
   - Renoise Play + ⏺ Bounce → Sample Recorder armé ; au prochain top
     de pattern, MIDI Start lance le séquenceur TD-3 + recording, en
     phase. Stop → sample créé.
3. **Mode B** (preview rapide) : ▶ Preview / ▶ Sync envoie les notes en
   MIDI temps réel (slide = legato, accent = vélocité).

### Multiplicateur de tempo (les deux éditeurs)

Popup `step =` : ×0.25 → 1/4, ×0.5 → 1/8, ×1 → 1/16 (défaut),
×2 → 1/32, ×4 → 1/64. Toujours synchro au BPM Renoise.

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
3. Dans Synthtribe : changer le MIDI Out vers "TD-3-Sniff".
4. Tout ce que Synthtribe envoie est affiché en hex horodaté ET relayé
   à la TD-3 normalement.

Alternative GUI sans Python : **MIDI-OX** (https://www.midiox.com/).

---

## Travaux confirmés

- ✅ Round-trip `.sqs` byte-exact (64 patterns, dump usine ou banc
  synthétique)
- ✅ Round-trip YAML / SysEx / `.seq` byte-exact via le pipeline complet
- ✅ SysEx 0x77 / 0x78 (Read/Write pattern) testé sur device
- ✅ SysEx 0x75 / 0x76 (Read config) + 0x1B (Set Clock) + 0x1C (Set
  Accent Threshold) testés sur device
- ✅ Preview MIDI live + sync BPM Renoise + step rate multiplicateur
- ✅ ⏺ Bounce → Sample Recorder via API Renoise 6.2
- ⚠️ Éditeur MIDI-live (32 pas + FX) : implémenté, sémantique
  ratchet/gate/slide à valider à l'oreille sur hardware

## Limites connues

- ❌ Sélection programmatique du slot actif sur la TD-3 : aucun opcode
  documenté **et Synthtribe ne le fait pas non plus** → manuel
  obligatoire sur la façade (le bouton « Sel slot » a été retiré).
- ❌ CC sound design (Resonance, Env Mod, Decay…) : Behringer n'expose
  que CC 74 (Cutoff). Tout le reste est sur les potards façade.
- ❌ Slide / accent en MIDI temps réel : approximations (slide = legato
  par overlap de notes). Pour le vrai comportement TB-303, passer par
  le séquenceur interne (Mode A).
- ❌ Chaînage de track : aucun opcode SysEx → `send-track` écrit les
  patterns et imprime la séquence à entrer manuellement.

## Licence

Code sous **PolyForm Noncommercial 1.0.0** (voir [`LICENSE`](LICENSE)) :
copie/modification/redistribution libres en usage non commercial.
Attributions des travaux de reverse-engineering tiers dans
[`CREDITS.md`](CREDITS.md). Le dump factory et les PDF Behringer ne sont
pas redistribués.
